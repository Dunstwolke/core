const std = @import("std");
const network = @import("network");

const rpc = @import("rpc.zig");

const RpcHostEndPoint = rpc.Definition.HostEndPoint(network.Socket.Reader, network.Socket.Writer, HostControl);

var command_queue: ControlQueue = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    command_queue = ControlQueue{ .arena = std.heap.ArenaAllocator.init(gpa.allocator()) };
    defer command_queue.arena.deinit();

    var listener = try network.Socket.create(.ipv4, .tcp);
    defer listener.close();

    try listener.enablePortReuse(true);
    try listener.bind(rpc.end_point);
    try listener.listen();

    var control_thread = try std.Thread.spawn(.{}, acceptConnectionsThread, .{listener});
    control_thread.detach();

    const json_parse_options = std.json.ParseOptions{
        .allocator = gpa.allocator(),
        .ignore_unknown_fields = false,
    };

    var services = std.StringArrayHashMap(Service).init(gpa.allocator());
    defer services.deinit();

    defer {
        var iter = services.iterator();
        while (iter.next()) |kv| {
            const svc = kv.value_ptr;
            if (svc.process) |process| {
                _ = process.kill() catch |err| {
                    std.log.err("failed to stop process {s}: {s}", .{ kv.key_ptr.*, @errorName(err) });
                };
                process.deinit();
            }
            std.json.parseFree(rpc.ServiceDescriptor, svc.descriptor, json_parse_options);
            gpa.allocator().free(kv.key_ptr.*);
        }
    }

    {
        var config_dir = try std.fs.cwd().openDir("system-root/config/services", .{ .iterate = true });
        defer config_dir.close();

        var iterator = config_dir.iterate();
        while (try iterator.next()) |entry| {
            const extension = std.fs.path.extension(entry.name);
            if (entry.kind != .File or !std.mem.eql(u8, extension, ".json"))
                continue;

            const file_data = try config_dir.readFileAlloc(gpa.allocator(), entry.name, 1 << 20);
            defer gpa.allocator().free(file_data);

            var stream = std.json.TokenStream.init(file_data);

            const descriptor = try std.json.parse(rpc.ServiceDescriptor, &stream, json_parse_options);
            errdefer std.json.parseFree(rpc.ServiceDescriptor, descriptor, json_parse_options);

            const name_dupe = try gpa.allocator().dupe(u8, entry.name[0 .. entry.name.len - extension.len]);
            errdefer gpa.allocator().free(name_dupe);

            try services.putNoClobber(name_dupe, Service{
                .process = null,
                .descriptor = descriptor,
                .name = name_dupe,
                .allocator = gpa.allocator(),
            });
        }
    }

    {
        var iter = services.iterator();
        while (iter.next()) |kv| {
            const svc = kv.value_ptr;
            if (svc.descriptor.autostart) {
                try svc.start();
            }
        }
    }

    while (true) {
        while (command_queue.active_queue.get()) |node| {
            defer @atomicStore(bool, &node.data.completed, true, .SeqCst);

            switch (node.data.command) {
                .startService => |*cmd| {
                    if (services.getPtr(cmd.service)) |svc| {
                        svc.start() catch |err| switch (err) {
                            error.FileNotFound => cmd.err = error.FileNotFound,
                            error.OutOfMemory => cmd.err = error.OutOfMemory,
                            else => cmd.err = error.IoError,
                        };
                    } else {
                        cmd.err = error.UnkownService;
                    }
                },
                .restartService => |*cmd| {
                    if (services.getPtr(cmd.service)) |svc| {
                        svc.restart() catch |err| {
                            cmd.err = switch (err) {
                                error.FileNotFound => error.FileNotFound,
                                error.OutOfMemory => error.OutOfMemory,
                                else => error.IoError,
                            };
                        };
                    } else {
                        cmd.err = error.UnkownService;
                    }
                },
                .stopService => |*cmd| {
                    if (services.getPtr(cmd.service)) |svc| {
                        svc.stop() catch |err| {
                            cmd.err = switch (err) {
                                error.FileNotFound => error.FileNotFound,
                                error.OutOfMemory => error.OutOfMemory,
                                else => error.IoError,
                            };
                        };
                    } else {
                        cmd.err = error.UnkownService;
                    }
                },
                .getServiceStatus => |*cmd| {
                    if (services.getPtr(cmd.service)) |svc| {
                        cmd.result = if (svc.process) |proc| rpc.ServiceStatus{
                            .online = true,
                            .pid = proc.pid,
                        } else rpc.ServiceStatus{
                            .online = false,
                            .pid = null,
                        };
                    } else {
                        cmd.err = error.UnkownService;
                    }
                },
                .createService => {
                    std.debug.print("cmd: createService\n", .{});
                },
                .deleteService => {
                    std.debug.print("cmd: deleteService\n", .{});
                },
                .getServiceDescriptor => {
                    std.debug.print("cmd: getServiceDescriptor\n", .{});
                },
            }
        }

        {
            var iter = services.iterator();
            while (iter.next()) |kv| {
                const svc = kv.value_ptr;
                if (svc.process) |proc| {
                    // TODO: Figure out how to check for process liveness

                    const waitres = std.os.waitpid(proc.pid, std.os.W.NOHANG);

                    const exit_code = if (waitres.status >= 0 and waitres.status <= 255) blk: {
                        std.debug.print("{} => {}\n", .{ proc.pid, waitres.status });
                        proc.deinit();
                        svc.process = null;
                        break :blk @truncate(u8, waitres.status);
                    } else null;

                    if (exit_code) |code| {
                        std.log.info("Service {s} exited with code {d}", .{ svc.name, code });

                        const restart = switch (svc.descriptor.restart) {
                            .no => false,
                            .@"on-failure" => (code == 0),
                            .always => true,
                        };

                        if (restart) {
                            try svc.start();
                        }
                    }
                }
            }
        }
        std.time.sleep(5 * std.time.ns_per_us);
    }
}

pub const Service = struct {
    allocator: std.mem.Allocator,
    process: ?*std.ChildProcess,
    descriptor: rpc.ServiceDescriptor,
    name: []const u8,

    pub fn start(svc: *Service) !void {
        if (svc.process != null)
            return;
        std.log.info("Starting service {s}...", .{svc.name});

        // TODO: Implement environment handling
        // var environment = try std.process.getEnvMap(gpa.allocator());
        // defer environment.deinit();

        var child = try std.ChildProcess.init(svc.descriptor.command, svc.allocator);
        errdefer child.deinit();

        // child.env_map = &environment;

        try child.spawn();

        svc.process = child;
    }

    fn stop(svc: *Service) !void {
        if (svc.process) |proc| {
            std.log.info("Stopping service {s}...", .{svc.name});
            const term = try proc.kill();
            std.log.info("exit code = {}\n", .{term});

            proc.deinit();

            svc.process = null;
        }
    }

    pub fn restart(svc: *Service) !void {
        try svc.stop();
        try svc.start();
    }
};

const Command = union(enum) {
    startService: struct {
        service: []const u8,
        err: ?rpc.ServiceControlError = null,
    },
    restartService: struct {
        service: []const u8,
        err: ?rpc.ServiceControlError = null,
    },
    stopService: struct {
        service: []const u8,
        err: ?rpc.ServiceControlError = null,
    },
    getServiceStatus: struct {
        service: []const u8,
        result: rpc.ServiceStatus = undefined,
        err: ?rpc.ServiceControlError = null,
    },
    createService: struct {
        desc: rpc.ServiceDescriptor,
        service: []const u8,
        err: ?rpc.CreateServiceError = null,
    },
    deleteService: struct {
        service: []const u8,
        err: ?rpc.ServiceControlError = null,
    },
    getServiceDescriptor: struct {
        service: []const u8,
        result: rpc.ServiceDescriptor = undefined,
        err: ?rpc.CreateServiceError = null,
    },
};

const ControlQueue = struct {
    const Self = @This();

    const WaitError = error{Timeout};

    const Data = struct {
        completed: bool,
        command: Command,

        pub fn wait(self: *const @This(), timeout: ?u64) WaitError!void {
            const start_time = std.time.nanoTimestamp();
            while (@atomicLoad(bool, &self.completed, .SeqCst) == false) {
                if (timeout) |t| {
                    const now = std.time.nanoTimestamp();
                    if (now >= start_time + t)
                        return error.Timeout;
                }
                std.time.sleep(100);
            }
            std.log.debug("waiting for command completion took {}", .{
                std.fmt.fmtDuration(@intCast(u64, std.time.nanoTimestamp() - start_time)),
            });
        }
    };

    const Queue = std.atomic.Queue(Data);
    const Node = Queue.Node;

    arena: std.heap.ArenaAllocator,
    arena_guard: std.Thread.Mutex = .{},
    free_queue: Queue = Queue.init(),
    active_queue: Queue = Queue.init(),

    pub fn execute(self: *Self, cmd: *Command, timeout: ?u64) WaitError!void {
        const node = if (self.free_queue.get()) |node|
            node
        else blk: {
            self.arena_guard.lock();
            defer self.arena_guard.unlock();
            break :blk self.arena.allocator().create(Node) catch @panic("out of memory");
        };
        defer self.free_queue.put(node);

        node.* = .{
            .data = .{
                .completed = false,
                .command = cmd.*,
            },
        };
        defer cmd.* = node.data.command;

        {
            self.active_queue.put(node);
            defer _ = self.active_queue.remove(node);
            try node.data.wait(timeout);
        }
    }
};

const HostControl = struct {
    dummy: u8 = 0,

    const command_timeout = 50 * std.time.ns_per_ms;

    pub fn startService(service: []const u8) rpc.ServiceControlError!void {
        var cmd = Command{ .startService = .{
            .service = service,
        } };

        try command_queue.execute(&cmd, command_timeout);
        if (cmd.startService.err) |err|
            return err;
    }
    pub fn restartService(service: []const u8) rpc.ServiceControlError!void {
        var cmd = Command{ .restartService = .{
            .service = service,
        } };

        try command_queue.execute(&cmd, command_timeout);
        if (cmd.restartService.err) |err|
            return err;
    }
    pub fn stopService(service: []const u8) rpc.ServiceControlError!void {
        var cmd = Command{ .stopService = .{
            .service = service,
        } };

        try command_queue.execute(&cmd, command_timeout);
        if (cmd.stopService.err) |err|
            return err;
    }
    pub fn getServiceStatus(service: []const u8) rpc.ServiceControlError!rpc.ServiceStatus {
        var cmd = Command{ .getServiceStatus = .{
            .service = service,
        } };

        try command_queue.execute(&cmd, command_timeout);
        if (cmd.getServiceStatus.err) |err|
            return err;
        return cmd.getServiceStatus.result;
    }
    pub fn createService(service: []const u8, desc: rpc.ServiceDescriptor) rpc.CreateServiceError!void {
        var cmd = Command{ .createService = .{
            .service = service,
            .desc = desc,
        } };

        try command_queue.execute(&cmd, command_timeout);
        if (cmd.createService.err) |err|
            return err;
    }
    pub fn deleteService(service: []const u8) rpc.ServiceControlError!void {
        var cmd = Command{ .deleteService = .{
            .service = service,
        } };

        try command_queue.execute(&cmd, command_timeout);
        if (cmd.deleteService.err) |err|
            return err;
    }
    pub fn getServiceDescriptor(service: []const u8) rpc.CreateServiceError!rpc.ServiceDescriptor {
        var cmd = Command{ .getServiceDescriptor = .{
            .service = service,
        } };

        try command_queue.execute(&cmd, command_timeout);
        if (cmd.getServiceDescriptor.err) |err|
            return err;
        return cmd.getServiceDescriptor.result;
    }
};

fn processManagementConnection(socket: network.Socket) !void {
    errdefer socket.close();

    const protocol_magic = [4]u8{ 0xf7, 0xcb, 0xbb, 0x05 };
    const protocol_version: u8 = 1;

    var thread_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = thread_allocator.deinit();

    const reader = socket.reader();
    const writer = socket.writer();

    var remote_auth: [protocol_magic.len]u8 = undefined;
    try reader.readNoEof(&remote_auth);
    if (!std.mem.eql(u8, &remote_auth, &protocol_magic))
        return error.ProtocolMismatch;

    var remote_version = try reader.readIntLittle(u8);
    if (remote_version != protocol_version)
        return error.ProtocolMismatch;

    var end_point = RpcHostEndPoint.init(thread_allocator.allocator(), reader, writer);
    defer end_point.destroy();

    var ctrl = HostControl{};

    try end_point.connect(&ctrl);

    try end_point.acceptCalls();
}

fn acceptConnectionsThread(listener: network.Socket) !void {
    while (true) {
        var client_socket = try listener.accept();
        errdefer client_socket.close();

        var management_thread = try std.Thread.spawn(.{}, processManagementConnection, .{client_socket});
        management_thread.detach();
    }
}

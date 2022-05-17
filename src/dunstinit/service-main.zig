const std = @import("std");
const args_parser = @import("args");
const network = @import("network");
const builtin = @import("builtin");
const dunst_environment = @import("dunst-environment");

const rpc = @import("rpc.zig");

fn printUsage(stream: anytype, exe_name: []const u8) !void {
    _ = exe_name;
    try stream.writeAll(
        \\dunstinit-daemon [-h] [-e]
        \\  -h, --help    Show this help
        \\  -e, --expose  Expose service to public interface
        \\
    );
}

const RpcHostEndPoint = rpc.Definition.HostEndPoint(network.Socket.Reader, network.Socket.Writer, HostControl);

var command_queue: ControlQueue = undefined;

const CliOptions = struct {
    help: bool = false,
    expose: bool = false,

    pub const shorthands = .{
        .h = "help",
        .e = "expose",
    };
};

pub fn main() !u8 {
    var stdout = std.io.getStdOut().writer();
    // var stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var cli = args_parser.parseForCurrentProcess(CliOptions, gpa.allocator(), .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        try printUsage(stdout, cli.executable_name.?);
        return 0;
    }

    command_queue = ControlQueue{ .arena = std.heap.ArenaAllocator.init(gpa.allocator()) };
    defer command_queue.arena.deinit();

    var listener = try network.Socket.create(.ipv4, .tcp);
    defer listener.close();

    try listener.enablePortReuse(true);

    try listener.bind(if (cli.options.expose)
        rpc.public_end_point
    else
        rpc.end_point);

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
            if (svc.process) |*process| {
                _ = process.kill() catch |err| {
                    std.log.err("failed to stop process {s}: {s}", .{ kv.key_ptr.*, @errorName(err) });
                };
            }
            std.json.parseFree(rpc.ServiceDescriptor, svc.descriptor, json_parse_options);
            gpa.allocator().free(kv.key_ptr.*);
        }
    }

    var services_dir = blk: {
        var config_root = try dunst_environment.openRoot(.config, .{});
        defer config_root.close();

        var config_dir = try config_root.makeOpenPath("services", .{ .iterate = true });
        errdefer config_dir.close();

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

        break :blk config_dir;
    };
    defer services_dir.close();

    {
        var iter = services.iterator();
        while (iter.next()) |kv| {
            const svc = kv.value_ptr;
            if (svc.descriptor.autostart) {
                svc.start() catch |err| {
                    std.log.err("failed to start service {s}: {s}", .{ kv.key_ptr.*, @errorName(err) });
                };
            }
        }
    }

    std.log.debug("ready.", .{});

    coreLoop(&services);

    return 0;
}

fn coreLoop(services: *std.StringArrayHashMap(Service)) void {
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
                            .pid = if (builtin.os.tag == .windows)
                                rpc.ProcessID{ .windows = GetProcessId(proc.handle) }
                            else
                                rpc.ProcessID{ .unix = proc.pid },
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
                periodicProcessCheck(svc) catch |err| {
                    std.log.err("failed to check process: {s}", .{@errorName(err)});
                };
            }
        }
        std.time.sleep(5 * std.time.ns_per_us);
    }

    return 0;
}

fn periodicProcessCheck(svc: *Service) !void {
    if (svc.process) |*proc| {
        // TODO: Figure out how to check for process liveness

        const exit_code = if (builtin.os.tag == .windows) blk: {
            std.os.windows.WaitForSingleObjectEx(proc.handle, 0, false) catch |err| switch (err) {
                error.WaitTimeOut => break :blk null,
                else => |e| return e,
            };

            const term = try proc.wait(); // this should not block

            svc.process = null;

            break :blk switch (term) {
                .Exited => |code| code,
                .Signal => unreachable, // not possible on windows,
                .Stopped => unreachable, // not possible on windows,
                .Unknown => 0xFF, // we just make something recognizable
            };

            //
        } else blk: {
            const waitres = std.os.waitpid(proc.pid, std.os.W.NOHANG);

            break :blk if (waitres.status >= 0 and waitres.status <= 255) b: {
                std.debug.print("{} => {}\n", .{ proc.pid, waitres.status });
                svc.process = null;
                break :b @truncate(u8, waitres.status);
            } else null;
        };

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

pub const Service = struct {
    allocator: std.mem.Allocator,
    process: ?std.ChildProcess,
    descriptor: rpc.ServiceDescriptor,
    name: []const u8,

    pub fn start(svc: *Service) !void {
        if (svc.process != null)
            return;
        std.log.info("Starting service {s}...", .{svc.name});

        // TODO: Implement environment handling
        // var environment = try std.process.getEnvMap(gpa.allocator());
        // defer environment.deinit();

        var child = std.ChildProcess.init(svc.descriptor.command, svc.allocator);

        // child.env_map = &environment;

        try child.spawn();

        svc.process = child;
    }

    fn stop(svc: *Service) !void {
        if (svc.process) |*proc| {
            std.log.info("Stopping service {s}...", .{svc.name});
            const term = try proc.kill();
            std.log.info("exit code = {}\n", .{term});

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

    const command_timeout = 250 * std.time.ns_per_ms;

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

fn processManagementConnection(allocator: std.mem.Allocator, socket: network.Socket) !void {
    const protocol_magic = rpc.protocol_magic;
    const protocol_version: u8 = rpc.protocol_version;

    const reader = socket.reader();
    const writer = socket.writer();

    var remote_auth: [protocol_magic.len]u8 = undefined;
    try reader.readNoEof(&remote_auth);
    if (!std.mem.eql(u8, &remote_auth, &protocol_magic))
        return error.ProtocolMismatch;

    var remote_version = try reader.readIntLittle(u8);
    if (remote_version != protocol_version)
        return error.ProtocolMismatch;

    var end_point = RpcHostEndPoint.init(allocator, reader, writer);
    defer end_point.destroy();

    var ctrl = HostControl{};

    try end_point.connect(&ctrl);

    try end_point.acceptCalls();
}

fn processManagementConnectionSafe(socket: network.Socket) void {
    defer socket.close();

    var thread_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = thread_allocator.deinit();

    processManagementConnection(thread_allocator.allocator(), socket) catch |err| {
        std.log.err("management thread died: {s}", .{@errorName(err)});
        if (builtin.mode == .Debug and builtin.os.tag != .windows) {
            // TODO: Fix windows stack trace printing on wine
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        }
    };
}

fn acceptConnectionsThread(listener: network.Socket) !void {
    while (true) {
        var client_socket = try listener.accept();
        errdefer client_socket.close();

        var management_thread = try std.Thread.spawn(.{}, processManagementConnectionSafe, .{client_socket});
        management_thread.detach();
    }
}

extern "kernel32" fn GetProcessId(process: std.os.windows.HANDLE) std.os.windows.DWORD;

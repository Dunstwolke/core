const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

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
            std.json.parseFree(ServiceDescriptor, svc.descriptor, json_parse_options);
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

            const descriptor = try std.json.parse(ServiceDescriptor, &stream, json_parse_options);
            errdefer std.json.parseFree(ServiceDescriptor, descriptor, json_parse_options);

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
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}

pub const Service = struct {
    allocator: std.mem.Allocator,
    process: ?*std.ChildProcess,
    descriptor: ServiceDescriptor,
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
};

pub const ServiceDescriptor = struct {
    autostart: bool = false,
    restart: Restart = .no,
    command: []const []const u8,
};

pub const Restart = enum {
    /// The service will never be restarted.
    no,

    /// The service will only be restarted if the exit code is not 0.
    @"on-failure",

    /// The service will always be restarted unless it is explicitly stopped.
    always,
};

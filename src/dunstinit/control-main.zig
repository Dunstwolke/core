const std = @import("std");
const args = @import("args");
const network = @import("network");

const rpc = @import("rpc.zig");

const RpcClientEndPoint = rpc.Definition.ClientEndPoint(network.Socket.Reader, network.Socket.Writer, ClientControl);

const ClientControl = struct {
    dummy: u8 = 0,
};
var client_ctrl = ClientControl{};

const CliOptions = struct {
    help: bool = false,
    host: ?[]const u8 = null,

    pub const shorthands = .{
        .h = "help",
        .H = "host",
    };
};

const CliVerb = union(enum) {
    start: Start,
    stop: Stop,
    restart: Restart,
    status: Status,

    pub const Start = struct {
        //
    };
    pub const Stop = struct {
        //
    };
    pub const Restart = struct {
        //
    };
    pub const Status = struct {
        //
    };
};

pub fn main() !u8 {
    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var cli = args.parseWithVerbForCurrentProcess(CliOptions, CliVerb, gpa.allocator(), .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        try printUsage(stdout, cli.executable_name.?);
        return 0;
    }

    if (cli.verb == null) {
        try printUsage(stderr, cli.executable_name.?);
        return 1;
    }

    var socket = if (cli.options.host) |host_name|
        try network.connectToHost(gpa.allocator(), host_name, rpc.dunstfabric_port, .tcp)
    else blk: {
        var socket = try network.Socket.create(.ipv4, .tcp);
        errdefer socket.close();

        try socket.connect(rpc.end_point);

        break :blk socket;
    };
    defer socket.close();

    var reader = socket.reader();
    var writer = socket.writer();

    try writer.writeAll(&rpc.protocol_magic);
    try writer.writeIntLittle(u8, rpc.protocol_version);

    var service = RpcClientEndPoint.init(gpa.allocator(), reader, writer);
    defer service.destroy();

    try service.connect(&client_ctrl);

    for (cli.positionals) |service_name| {
        switch (cli.verb.?) {
            .start => |verb| {
                _ = verb;
                service.invoke("startService", .{service_name}) catch |err| {
                    try stderr.print("failed to start service {s}: {s}\n", .{ service_name, getErrorDescription(err) });
                };
            },
            .stop => |verb| {
                _ = verb;
                service.invoke("stopService", .{service_name}) catch |err| {
                    try stderr.print("failed to stop service {s}: {s}\n", .{ service_name, getErrorDescription(err) });
                };
            },
            .restart => |verb| {
                _ = verb;
                service.invoke("restartService", .{service_name}) catch |err| {
                    try stderr.print("failed to restart service {s}: {s}\n", .{ service_name, getErrorDescription(err) });
                };
            },
            .status => |verb| {
                _ = verb;
                const status: rpc.ServiceStatus = service.invoke("getServiceStatus", .{service_name}) catch |err| {
                    try stderr.print("failed to restart service {s}: {s}\n", .{ service_name, getErrorDescription(err) });
                    continue;
                };
                if (status.online) {
                    try stdout.print("{s} is online: pid={d}\n", .{ service_name, status.pid });
                } else {
                    try stdout.print("{s} is offline.\n", .{service_name});
                }
            },
        }
    }

    try service.shutdown();

    return 0;
}

fn getErrorDescription(err: anyerror) []const u8 {
    return switch (err) {
        error.Timeout => "The remote command timed out.",
        error.FileNotFound => "The service executable was not found.",
        error.IoError => "There was an error starting the remote service.",

        else => |e| @errorName(e),
    };
}

fn printUsage(stream: anytype, exe_name: []const u8) !void {
    _ = exe_name;
    try stream.writeAll(
        \\dunstinit-daemon [-h] [-H <ip>] <verb>
        \\Options:
        \\  -h, --help      Show this help
        \\  -H, --host <ip> Connects to the given host at <ip>.
        \\
        \\Verbs:
        \\  start <service>
        \\      Starts the <service>.
        \\  stop <service>
        \\      Stops the <service>.
        \\  restart <service>
        \\      Restarts the <service>.
        \\  status <service>
        \\      Prints the status of <service>.
        \\
    );
}

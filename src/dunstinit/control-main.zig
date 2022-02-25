const std = @import("std");
const args = @import("args");
const network = @import("network");

const rpc = @import("rpc.zig");

const RpcClientEndPoint = rpc.Definition.ClientEndPoint(network.Socket.Reader, network.Socket.Writer, ClientControl);

var global_shutdown = false;

const ClientControl = struct {
    dummy: u8 = 0,
};

var client_ctrl = ClientControl{};

const CliOptions = struct {
    help: bool = false,
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
    var stdout = std.io.getStdOut();
    var stderr = std.io.getStdErr();

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

    var socket = try network.Socket.create(.ipv4, .tcp);
    defer socket.close();

    try socket.connect(rpc.end_point);

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
                try service.invoke("startService", .{service_name});
            },
            .stop => |verb| {
                _ = verb;
                try service.invoke("stopService", .{service_name});
            },
            .restart => |verb| {
                _ = verb;
                try service.invoke("restartService", .{service_name});
            },
            .status => |verb| {
                _ = verb;
            },
        }
    }

    return 0;
}

fn printUsage(stream: anytype, exe_name: []const u8) !void {
    _ = exe_name;
    try stream.writeAll(
        \\BLAH BLAH BLAH
        \\
    );
}

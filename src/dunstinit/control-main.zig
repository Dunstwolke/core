const std = @import("std");
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

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

    try service.invoke("startService", .{"date"});
}

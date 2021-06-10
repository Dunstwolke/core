//! This implements a stubbed application that just runs the protocol
//! and will not do anything useful.
//! 
//! This is helpful to debug the protocol network implementation

const std = @import("std");
const network = @import("network");
const protocol = @import("dunstblick-protocol");

pub fn main() !void {
    var listener = try network.Socket.create(.ipv4, .tcp);
    defer listener.close();

    try listener.bindToPort(1337);

    try listener.listen();

    std.log.info("listening on 0.0.0.0:1337", .{});

    while (true) {
        var client = try listener.accept();
        defer client.close();

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();

        var set = try network.SocketSet.init(&gpa.allocator);
        defer set.deinit();

        var server = protocol.tcp.ServerStateMachine(network.Socket.Writer).init(&gpa.allocator, client.writer());
        defer server.deinit();

        while (true) {
            _ = try network.waitForSocketEvent(&set, null);

            if (set.isReadyRead(client)) {
                var receive_buffer: [8192]u8 = undefined;

                const len = try client.receive(&receive_buffer);

                var offset: usize = 0;
                while (offset < len) {
                    const event_info = try server.pushData(receive_buffer[offset..len]);
                    offset += event_info.consumed;
                    if (event_info.event) |event| {
                        switch (event) {
                            else => std.log.info("received unhandled event: {}", .{event}),
                        }
                    }
                }
            }
        }
    }
}

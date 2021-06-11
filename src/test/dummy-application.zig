//! This implements a stubbed application that just runs the protocol
//! and will not do anything useful.
//! 
//! This is helpful to debug the protocol network implementation

const std = @import("std");
const network = @import("network");
const protocol = @import("dunstblick-protocol");

const resources = [_][]const u8{
    @embedFile("../images/kristall-32.png"),
    @embedFile("../images/person-female-01.png"),
    @embedFile("../images/person-male-01.png"),
    @embedFile("../images/small-test.png"),
};

pub fn main() !void {
    var listener = try network.Socket.create(.ipv4, .tcp);
    defer listener.close();

    try listener.bindToPort(1337);

    try listener.listen();

    std.log.info("listening on 0.0.0.0:1337", .{});

    while (true) {
        var client = try listener.accept();
        defer client.close();

        handleConnection(client) catch |err| {
            std.log.err("connection failed: {}", .{err});
        };
    }
}

fn handleConnection(client: network.Socket) !void {
    std.log.info("client connected from {}", .{
        try client.getRemoteEndPoint(),
    });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var set = try network.SocketSet.init(&gpa.allocator);
    defer set.deinit();

    try set.add(client, .{ .read = true, .write = false });

    var server = protocol.tcp.ServerStateMachine(network.Socket.Writer).init(&gpa.allocator, client.writer());
    defer server.deinit();

    while (true) {
        _ = try network.waitForSocketEvent(&set, null);

        if (set.isReadyRead(client)) {
            var receive_buffer: [8192]u8 = undefined;

            const len = try client.receive(&receive_buffer);
            if (len == 0)
                return error.RemoteHostClosed;

            var offset: usize = 0;
            while (offset < len) {
                const event_info = try server.pushData(receive_buffer[offset..len]);
                offset += event_info.consumed;
                if (event_info.event) |event| {
                    switch (event) {
                        .initiate_handshake => |hs| {
                            const auth_action = try server.acknowledgeHandshake(.{
                                .requires_username = false,
                                .requires_password = false,
                                .rejects_username = hs.has_username, // reject both username and password if present
                                .rejects_password = hs.has_password, // reject both username and password if present
                            });

                            if (auth_action != .send_auth_result)
                                return error.Unexpected;

                            try server.sendAuthenticationResult(.success, false);
                        },
                        .connect_header => |hdr| {
                            std.log.info("client specs: {}", .{hdr});

                            const headers = blk: {
                                var items: [resources.len]protocol.tcp.ConnectResponseItem = undefined;
                                for (items) |*desc, i| {
                                    desc.* = .{
                                        .id = @intToEnum(protocol.ResourceID, @truncate(u32, i + 1)),
                                        .size = @intCast(u32, resources[i].len),
                                        .hash = protocol.computeResourceHash(resources[i]),
                                        .type = .bitmap,
                                    };
                                }
                                break :blk items;
                            };

                            try server.sendConnectResponse(&headers);
                        },
                        .resource_request => |info| {
                            std.log.info("client requests the following resources: {any}", .{info.requested_resources});

                            for (info.requested_resources) |res_id| {
                                try server.sendResourceHeader(res_id, resources[@enumToInt(res_id) - 1]);
                            }
                        },
                        else => std.log.info("received unhandled event: {}", .{event}),
                    }
                }
            }
        }
    }
}

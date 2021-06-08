const std = @import("std");

pub const udp = @import("udp.zig");

pub const tcp = struct {
    pub usingnamespace v1;

    pub const v1 = @import("tcp/v1.zig");

    const client_state_machine = @import("tcp/client_state_machine.zig");
    const server_state_machine = @import("tcp/server_state_machine.zig");

    pub const ServerStateMachine = server_state_machine.ServerStateMachine;
    pub const ClientStateMachine = client_state_machine.ClientStateMachine;
};

pub usingnamespace @import("data-types.zig");

pub const Decoder = @import("decoder.zig").Decoder;

pub const ZigZagInt = @import("zigzagint.zig");

pub const Encoder = @import("encoder.zig").Encoder;

pub fn makeEncoder(stream: anytype) Encoder(@TypeOf(stream)) {
    return Encoder(@TypeOf(stream)).init(stream);
}

pub fn beginDisplayCommandEncoding(stream: anytype, command: DisplayCommand) !Encoder(@TypeOf(stream)) {
    var enc = Encoder(@TypeOf(stream)).init(stream);
    try enc.writeByte(@enumToInt(command));
    return enc;
}

pub fn beginApplicationCommandEncoding(stream: anytype, command: ApplicationCommand) !Encoder(@TypeOf(stream)) {
    var enc = Encoder(@TypeOf(stream)).init(stream);
    try enc.writeByte(@enumToInt(command));
    return enc;
}

pub const DisplayCommand = enum(u8) {
    disconnect = 0, // (reason)
    uploadResource = 1, // (rid, kind, data)
    addOrUpdateObject = 2, // (obj)
    removeObject = 3, // (oid)
    setView = 4, // (rid)
    setRoot = 5, // (oid)
    setProperty = 6, // (oid, name, value) // "unsafe command", uses the serverside object type or fails of property
    clear = 7, // (oid, name)
    insertRange = 8, // (oid, name, index, count, value …) // manipulate lists
    removeRange = 9, // (oid, name, index, count) // manipulate lists
    moveRange = 10, // (oid, name, indexFrom, indexTo, count) // manipulate lists
    _,
};

pub const ApplicationCommand = enum(u8) {
    eventCallback = 1, // (cid)
    propertyChanged = 2, // (oid, name, type, value)
    _,
};

test {
    _ = makeEncoder;
    _ = beginDisplayCommandEncoding;
    _ = beginApplicationCommandEncoding;
    _ = Decoder;
    _ = ZigZagInt;
    _ = Encoder;
    _ = tcp.v1;
    _ = tcp.ServerStateMachine;
    _ = tcp.ClientStateMachine;
}

test "Network protocol implementation (unencrypted, no authentication)" {
    const Stream = std.io.FixedBufferStream([]u8);

    var backing_buffer: [4096]u8 = undefined;
    var stream = Stream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(Stream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(Stream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    try client.initiateHandshake(null, null);

    {
        const result = try server.pushData(stream.getWritten());
        try std.testing.expectEqual(stream.getPos(), result.consumed);
        try std.testing.expect(result.event != null);
        try std.testing.expectEqual(std.meta.Tag(tcp.server_state_machine.ReceiveEvent).initiate_handshake, result.event.?);

        const msg = result.event.?.initiate_handshake;
        try std.testing.expectEqual(false, msg.has_username);
        try std.testing.expectEqual(false, msg.has_password);

        stream.reset();
    }

    {
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.send_auth_result, auth_action);
    }

    // {
    //     const result = try client.pushData(stream.getWritten());
    //     try std.testing.expectEqual(stream.getPos(), result.consumed);
    //     try std.testing.expect(result.event != null);
    //     try std.testing.expectEqual(std.meta.Tag(tcp.client_state_machine.ReceiveEvent).acknowledge_handshake, result.event.?);

    //     const msg = result.event.?.acknowledge_handshake;

    //     stream.reset();
    // }
}

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

pub const layout_format = @import("layout.zig");

pub const enums = @import("enums.zig");

pub usingnamespace @import("data-types.zig");

pub const Value = @import("value.zig").Value;

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

    // pure data declaration, must always be valid
    std.testing.refAllDecls(layout_format);
}

const TestStream = std.io.FixedBufferStream([]u8);

/// Computes the hash for a resource file
pub fn computeResourceHash(data: []const u8) ResourceHash {
    var hash: ResourceHash = undefined;
    std.mem.writeIntLittle(u64, &hash, std.hash.Fnv1a_64.hash(data));
    return hash;
}

fn expectServerEvent(
    stream: *TestStream,
    server: *tcp.ServerStateMachine(TestStream.Writer),
    comptime event_type: std.meta.Tag(tcp.server_state_machine.ReceiveEvent),
) !std.meta.fieldInfo(
    tcp.server_state_machine.ReceiveEvent,
    @field(std.meta.FieldEnum(tcp.server_state_machine.ReceiveEvent), @tagName(event_type)),
).field_type {
    const name = @tagName(event_type);

    const data = stream.getWritten();

    // Simulate wild packet fragmentation based on the packet itself
    var rng_engine = std.rand.DefaultPrng.init(@enumToInt(event_type) + 16 * data.len);
    const random = &rng_engine.random;

    var i: usize = 0;
    while (i < data.len) {
        const partial_len = if (data.len - i > 1)
            random.intRangeLessThan(usize, 1, data.len - i)
        else
            data.len - i;
        std.debug.assert(partial_len > 0);

        const result = try server.pushData(data[i..][0..partial_len]);
        i += result.consumed;
        if (result.event == null) {
            continue;
        }

        try std.testing.expectEqual(stream.getPos(), i);
        try std.testing.expectEqual(event_type, result.event.?);

        return @field(result.event.?, name);
    }

    return error.ParserMissedEvent;
}

fn expectClientEvent(
    stream: *TestStream,
    client: *tcp.ClientStateMachine(TestStream.Writer),
    comptime event_type: std.meta.Tag(tcp.client_state_machine.ReceiveEvent),
) !std.meta.fieldInfo(
    tcp.client_state_machine.ReceiveEvent,
    @field(std.meta.FieldEnum(tcp.client_state_machine.ReceiveEvent), @tagName(event_type)),
).field_type {
    const name = @tagName(event_type);

    const data = stream.getWritten();

    // Simulate wild packet fragmentation based on the packet itself
    var rng_engine = std.rand.DefaultPrng.init(@enumToInt(event_type) + 16 * data.len);
    const random = &rng_engine.random;

    var i: usize = 0;
    while (i < data.len) {
        const partial_len = if (data.len - i > 1)
            random.intRangeLessThan(usize, 1, data.len - i)
        else
            data.len - i;
        std.debug.assert(partial_len > 0);

        const result = try client.pushData(data[i..][0..partial_len]);
        i += result.consumed;
        if (result.event == null) {
            continue;
        }

        try std.testing.expectEqual(stream.getPos(), i);
        try std.testing.expectEqual(event_type, result.event.?);

        return @field(result.event.?, name);
    }

    return error.ParserMissedEvent;
}

test "Network protocol implementation (unencrypted, no authentication)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake(null, null);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(false, msg.has_username);
        try std.testing.expectEqual(false, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.send_auth_result, auth_action);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(true, msg.ok());
    }

    {
        stream.reset();
        try server.sendAuthenticationResult(.success, false);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .authenticate_result);

        try std.testing.expectEqual(tcp.AuthenticationResult.Result.success, msg.result);
    }

    try std.testing.expectEqual(false, client.crypto.encryption_enabled);
    try std.testing.expectEqual(false, server.crypto.encryption_enabled);

    try testCommonHandshake(&server, &client, &stream, .many, .many);
}

test "Network protocol implementation (unencrypted, username)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake("Ziggy Stardust", null);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(true, msg.has_username);
        try std.testing.expectEqual(false, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.expect_auth_info, auth_action);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(true, msg.ok());
    }

    {
        stream.reset();
        try client.sendAuthenticationInfo();
    }

    {
        const msg = try expectServerEvent(&stream, &server, .authenticate_info);

        try std.testing.expect(msg.username != null);
        try std.testing.expectEqualStrings("Ziggy Stardust", msg.username.?);
        try std.testing.expectEqual(false, msg.requires_key);
    }

    {
        stream.reset();
        try server.sendAuthenticationResult(.success, false);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .authenticate_result);

        try std.testing.expectEqual(tcp.AuthenticationResult.Result.success, msg.result);
    }

    try std.testing.expectEqual(false, client.crypto.encryption_enabled);
    try std.testing.expectEqual(false, server.crypto.encryption_enabled);

    try testCommonHandshake(&server, &client, &stream, .many, .many);
}

test "Network protocol implementation (unencrypted, only password)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    const test_key: [32]u8 = "0123456789ABCDEF0123456789ABCDEF".*;

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake(null, test_key);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(false, msg.has_username);
        try std.testing.expectEqual(true, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.expect_auth_info, auth_action);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(true, msg.ok());
    }

    {
        stream.reset();
        try client.sendAuthenticationInfo();
    }

    {
        const msg = try expectServerEvent(&stream, &server, .authenticate_info);

        try std.testing.expectEqual(@as(?[]const u8, null), msg.username);
        try std.testing.expectEqual(true, msg.requires_key);

        // The key here is usually fetched either from a static config
        // for a normal server key or a user database.
        const auth_result = server.setKeyAndVerify(test_key);

        try std.testing.expectEqual(tcp.server_state_machine.AuthenticationResult.success, auth_result);
    }

    {
        stream.reset();
        try server.sendAuthenticationResult(.success, false);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .authenticate_result);

        try std.testing.expectEqual(tcp.AuthenticationResult.Result.success, msg.result);
    }

    try std.testing.expectEqual(false, client.crypto.encryption_enabled);
    try std.testing.expectEqual(false, server.crypto.encryption_enabled);

    try testCommonHandshake(&server, &client, &stream, .many, .many);
}

test "Network protocol implementation (unencrypted, username + password)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    const test_key: [32]u8 = "0123456789ABCDEF0123456789ABCDEF".*;

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake("Zero the Hero", test_key);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(true, msg.has_username);
        try std.testing.expectEqual(true, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.expect_auth_info, auth_action);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(true, msg.ok());
    }

    {
        stream.reset();
        try client.sendAuthenticationInfo();
    }

    {
        const msg = try expectServerEvent(&stream, &server, .authenticate_info);

        try std.testing.expect(msg.username != null);
        try std.testing.expectEqualStrings("Zero the Hero", msg.username.?);
        try std.testing.expectEqual(true, msg.requires_key);

        // The key here is usually fetched either from a static config
        // for a normal server key or a user database.
        const auth_result = server.setKeyAndVerify(test_key);

        try std.testing.expectEqual(tcp.server_state_machine.AuthenticationResult.success, auth_result);
    }

    {
        stream.reset();
        try server.sendAuthenticationResult(.success, false);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .authenticate_result);

        try std.testing.expectEqual(tcp.AuthenticationResult.Result.success, msg.result);
    }

    try std.testing.expectEqual(false, client.crypto.encryption_enabled);
    try std.testing.expectEqual(false, server.crypto.encryption_enabled);

    try testCommonHandshake(&server, &client, &stream, .many, .many);
}

test "Network protocol implementation (encrypted, only password)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    const test_key: [32]u8 = "0123456789ABCDEF0123456789ABCDEF".*;

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake(null, test_key);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(false, msg.has_username);
        try std.testing.expectEqual(true, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.expect_auth_info, auth_action);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(true, msg.ok());
    }

    {
        stream.reset();
        try client.sendAuthenticationInfo();
    }

    {
        const msg = try expectServerEvent(&stream, &server, .authenticate_info);

        try std.testing.expectEqual(@as(?[]const u8, null), msg.username);
        try std.testing.expectEqual(true, msg.requires_key);

        // The key here is usually fetched either from a static config
        // for a normal server key or a user database.
        const auth_result = server.setKeyAndVerify(test_key);

        try std.testing.expectEqual(tcp.server_state_machine.AuthenticationResult.success, auth_result);
    }

    {
        stream.reset();
        try server.sendAuthenticationResult(.success, true);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .authenticate_result);

        try std.testing.expectEqual(tcp.AuthenticationResult.Result.success, msg.result);
    }

    try std.testing.expectEqual(true, client.crypto.encryption_enabled);
    try std.testing.expectEqual(true, server.crypto.encryption_enabled);

    try testCommonHandshake(&server, &client, &stream, .many, .many);
}

test "Network protocol implementation (encrypted, username + password)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    const test_key: [32]u8 = "0123456789ABCDEF0123456789ABCDEF".*;

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake("Ultraman Zero", test_key);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(true, msg.has_username);
        try std.testing.expectEqual(true, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.expect_auth_info, auth_action);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(true, msg.ok());
    }

    {
        stream.reset();
        try client.sendAuthenticationInfo();
    }

    {
        const msg = try expectServerEvent(&stream, &server, .authenticate_info);

        try std.testing.expect(msg.username != null);
        try std.testing.expectEqualStrings("Ultraman Zero", msg.username.?);
        try std.testing.expectEqual(true, msg.requires_key);

        // The key here is usually fetched either from a static config
        // for a normal server key or a user database.
        const auth_result = server.setKeyAndVerify(test_key);

        try std.testing.expectEqual(tcp.server_state_machine.AuthenticationResult.success, auth_result);
    }

    {
        stream.reset();
        try server.sendAuthenticationResult(.success, true);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .authenticate_result);

        try std.testing.expectEqual(tcp.AuthenticationResult.Result.success, msg.result);
    }

    try std.testing.expectEqual(true, client.crypto.encryption_enabled);
    try std.testing.expectEqual(true, server.crypto.encryption_enabled);

    try testCommonHandshake(&server, &client, &stream, .many, .many);
}

const TestResourceCount = enum { none, one, many };

/// Run the test suite for encryption/auth agnostic code.
/// This must run with any encryption/auth combination
fn testCommonHandshake(
    server: *tcp.ServerStateMachine(TestStream.Writer),
    client: *tcp.ClientStateMachine(TestStream.Writer),
    stream: *TestStream,
    /// number of available resources
    resource_count: TestResourceCount,
    /// number of requested resources
    request_count: TestResourceCount,
) !void {
    const all_resources = [4][]const u8{
        "Hello, i am a resource",
        "",
        &("THIS IS A VERY LONG AND LOUD RESOURCE. I AM SHOUTING! ".* ** 50),
        "I am a resource as well. See my might!",
    };

    const all_resources_descriptors: [all_resources.len]tcp.ConnectResponseItem = blk: {
        var descriptors: [all_resources.len]tcp.ConnectResponseItem = undefined;
        for (descriptors) |*desc, i| {
            desc.* = .{
                .id = @intToEnum(ResourceID, @truncate(u32, i)),
                .type = @intToEnum(ResourceKind, @truncate(u8, i % 3)),
                .size = @truncate(u32, all_resources[i].len),
                .hash = computeResourceHash(all_resources[i]),
            };
        }
        break :blk descriptors;
    };

    const resource_limit = switch (resource_count) {
        .none => @as(usize, 0),
        .one => @as(usize, 1),
        .many => @as(usize, all_resources.len),
    };

    const resources = all_resources[0..resource_limit];
    const resources_descriptors = all_resources_descriptors[0..resource_limit];

    const dummy_caps = tcp.ClientCapabilities{
        .mouse = true,
        .keyboard = true,
        .touch = false,
        .highdpi = false,
        .tiltable = true,
        .resizable = false,
        .req_accessibility = true,
    };

    {
        stream.reset();
        try client.sendConnectHeader(640, 480, dummy_caps);
    }

    {
        const msg = try expectServerEvent(stream, server, .connect_header);
        try std.testing.expectEqual(@as(u16, 640), msg.screen_width);
        try std.testing.expectEqual(@as(u16, 480), msg.screen_height);
        try std.testing.expectEqual(dummy_caps, msg.capabilities);
    }

    {
        stream.reset();
        try server.sendConnectResponse(resources_descriptors);
    }

    // This is tested for the consume value.
    // In this case, sendConnectResponse writes several messages at once
    var stream_offset: usize = 0;

    {
        const result = try client.pushData(stream.getWritten()[stream_offset..]);
        stream_offset += result.consumed;

        try std.testing.expect((try stream.getPos()) >= result.consumed);
        try std.testing.expect(result.event != null);
        try std.testing.expectEqual(std.meta.Tag(tcp.client_state_machine.ReceiveEvent).connect_response, result.event.?);

        const msg = result.event.?.connect_response;

        try std.testing.expectEqual(resources.len, msg.resource_count);
    }

    if (resources_descriptors.len > 0) {
        for (resources_descriptors) |desc, i| {
            const result = try client.pushData(stream.getWritten()[stream_offset..]);
            stream_offset += result.consumed;

            try std.testing.expect((try stream.getPos()) >= result.consumed);
            try std.testing.expect(result.event != null);
            try std.testing.expectEqual(std.meta.Tag(tcp.client_state_machine.ReceiveEvent).connect_response_item, result.event.?);

            const msg = result.event.?.connect_response_item;

            try std.testing.expectEqual(i, msg.index);
            try std.testing.expectEqual(desc, msg.descriptor);
        }

        try std.testing.expectEqual(stream.getPos(), stream_offset);

        if (resources_descriptors.len > 0) {
            const all_requested_resources = [_]ResourceID{
                all_resources_descriptors[0].id,
                all_resources_descriptors[1].id,
            };

            // many requests => many resources
            std.debug.assert(!(request_count == .many) or (resource_count == .many));

            const requested_resources = switch (request_count) {
                .none => all_requested_resources[0..0],
                .one => all_requested_resources[0..1],
                .many => &all_requested_resources,
            };

            {
                stream.reset();
                try client.sendResourceRequest(requested_resources);
            }

            {
                const msg = try expectServerEvent(stream, server, .resource_request);
                try std.testing.expectEqualSlices(ResourceID, requested_resources, msg.requested_resources);
            }

            for (requested_resources) |id, i| {
                {
                    stream.reset();
                    try server.sendResourceHeader(resources_descriptors[i].id, resources[i]);
                }

                {
                    const msg = try expectClientEvent(stream, client, .resource_header);
                    try std.testing.expectEqual(resources_descriptors[i].id, msg.resource_id);
                    try std.testing.expectEqualSlices(u8, resources[i], msg.data);
                }
            }
        }
    }

    try std.testing.expectEqual(true, server.isConnectionEstablished());

    try std.testing.expectEqual(true, client.isConnectionEstablished());

    // The connection is now fully established, we can now send arbitrary messages between the client
    // and the server \o/

    // Test some basic back-and-forth of some messages

    {
        stream.reset();
        try server.sendMessage("Hello, Client!");
    }

    {
        const msg = try expectClientEvent(stream, client, .message);
        try std.testing.expectEqualStrings("Hello, Client!", msg);
    }

    {
        stream.reset();
        try server.sendMessage("This is a second message...");
    }

    {
        const msg = try expectClientEvent(stream, client, .message);
        try std.testing.expectEqualStrings("This is a second message...", msg);
    }

    {
        stream.reset();
        try client.sendMessage("Hello, Server!");
    }

    {
        const msg = try expectServerEvent(stream, server, .message);
        try std.testing.expectEqualStrings("Hello, Server!", msg);
    }

    // Do some stress testing with bigger, partially transferred message which require re-assembly

    {
        var rng_engine = std.rand.DefaultPrng.init(13_37);
        const random = &rng_engine.random;

        var i: usize = 0;
        while (i < 1_000) : (i += 1) {
            var tmp_message_buffer: [3800]u8 = undefined;

            const tmp_message = tmp_message_buffer[0..random.intRangeLessThan(usize, 1, tmp_message_buffer.len)];
            random.bytes(tmp_message);

            if (random.boolean()) {
                // Client -> Server
                {
                    stream.reset();
                    try client.sendMessage(tmp_message);
                }

                {
                    const msg = try expectServerEvent(stream, server, .message);
                    try std.testing.expectEqualSlices(u8, tmp_message, msg);
                }
            } else {
                // Server -> Client
                {
                    stream.reset();
                    try server.sendMessage(tmp_message);
                }

                {
                    const msg = try expectClientEvent(stream, client, .message);
                    try std.testing.expectEqualSlices(u8, tmp_message, msg);
                }
            }
        }
    }
}

test "Network protocol implementation (handshake fail, 'requires username')" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake(null, null);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(false, msg.has_username);
        try std.testing.expectEqual(false, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = true,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.drop, auth_action);
    }

    try std.testing.expectEqual(true, server.isFaulted());

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(true, msg.requires_username);
        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(false, msg.ok());
    }

    try std.testing.expectEqual(true, client.isFaulted());
}

test "Network protocol implementation (handshake fail, 'requires password')" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake(null, null);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(false, msg.has_username);
        try std.testing.expectEqual(false, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = true,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.drop, auth_action);
    }

    try std.testing.expectEqual(true, server.isFaulted());

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(true, msg.requires_password);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(false, msg.ok());
    }

    try std.testing.expectEqual(true, client.isFaulted());
}

test "Network protocol implementation (handshake fail, 'rejected username')" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake("Major Zero", null);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(true, msg.has_username);
        try std.testing.expectEqual(false, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = true,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.drop, auth_action);
    }

    try std.testing.expectEqual(true, server.isFaulted());

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(true, msg.rejects_username);
        try std.testing.expectEqual(false, msg.rejects_password);

        try std.testing.expectEqual(false, msg.ok());
    }

    try std.testing.expectEqual(true, client.isFaulted());
}

test "Network protocol implementation (handshake fail, 'rejected password')" {
    const test_key: [32]u8 = "0123456789ABCDEF0123456789ABCDEF".*;

    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake(null, test_key);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(false, msg.has_username);
        try std.testing.expectEqual(true, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = true,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.drop, auth_action);
    }

    try std.testing.expectEqual(true, server.isFaulted());

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.rejects_username);
        try std.testing.expectEqual(true, msg.rejects_password);

        try std.testing.expectEqual(false, msg.ok());
    }

    try std.testing.expectEqual(true, client.isFaulted());
}

test "Network protocol implementation (handshake fail: invalid authentication)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    const client_key: [32]u8 = "0123456789ABCDEF0123456789ABCDEF".*;
    const server_key: [32]u8 = "FEDCBA9876543210FEDCBA9876543210".*;

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    {
        stream.reset();
        try client.initiateHandshake("Bahamut ZERO", client_key);
    }

    {
        const msg = try expectServerEvent(&stream, &server, .initiate_handshake);

        try std.testing.expectEqual(true, msg.has_username);
        try std.testing.expectEqual(true, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.expect_auth_info, auth_action);
    }

    {
        const msg = try expectClientEvent(&stream, &client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(true, msg.ok());
    }

    {
        stream.reset();
        try client.sendAuthenticationInfo();
    }

    {
        const msg = try expectServerEvent(&stream, &server, .authenticate_info);

        try std.testing.expect(msg.username != null);
        try std.testing.expectEqualStrings("Bahamut ZERO", msg.username.?);
        try std.testing.expectEqual(true, msg.requires_key);

        // The key here is usually fetched either from a static config
        // for a normal server key or a user database.
        const auth_result = server.setKeyAndVerify(server_key);

        try std.testing.expectEqual(tcp.server_state_machine.AuthenticationResult.failure, auth_result);
    }

    {
        stream.reset();
        try server.sendAuthenticationResult(.invalid_credentials, false);
    }

    try std.testing.expectEqual(true, server.isFaulted());

    {
        const msg = try expectClientEvent(&stream, &client, .authenticate_result);

        try std.testing.expectEqual(tcp.AuthenticationResult.Result.invalid_credentials, msg.result);
    }

    try std.testing.expectEqual(true, client.isFaulted());
}

fn testDefaultCryptoHandshake(
    server: *tcp.ServerStateMachine(TestStream.Writer),
    client: *tcp.ClientStateMachine(TestStream.Writer),
    stream: *TestStream,
) !void {
    {
        stream.reset();
        try client.initiateHandshake(null, null);
    }

    {
        const msg = try expectServerEvent(stream, server, .initiate_handshake);

        try std.testing.expectEqual(false, msg.has_username);
        try std.testing.expectEqual(false, msg.has_password);
    }

    {
        stream.reset();
        const auth_action = try server.acknowledgeHandshake(.{
            .requires_username = false,
            .requires_password = false,
            .rejects_username = false,
            .rejects_password = false,
        });
        try std.testing.expectEqual(tcp.server_state_machine.AuthAction.send_auth_result, auth_action);
    }

    {
        const msg = try expectClientEvent(stream, client, .acknowledge_handshake);

        try std.testing.expectEqual(false, msg.requires_password);
        try std.testing.expectEqual(false, msg.requires_username);
        try std.testing.expectEqual(false, msg.rejects_password);
        try std.testing.expectEqual(false, msg.rejects_username);

        try std.testing.expectEqual(true, msg.ok());
    }

    {
        stream.reset();
        try server.sendAuthenticationResult(.success, false);
    }

    {
        const msg = try expectClientEvent(stream, client, .authenticate_result);

        try std.testing.expectEqual(tcp.AuthenticationResult.Result.success, msg.result);
    }

    try std.testing.expectEqual(false, client.crypto.encryption_enabled);
    try std.testing.expectEqual(false, server.crypto.encryption_enabled);
}

test "Network protocol implementation (unencrypted, no authentication, many resources, no request)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    try testDefaultCryptoHandshake(&server, &client, &stream);

    try testCommonHandshake(&server, &client, &stream, .many, .none);
}

test "Network protocol implementation (unencrypted, no authentication, many resources, one request)" {
    var backing_buffer: [4096]u8 = undefined;
    var stream = TestStream{ .buffer = &backing_buffer, .pos = 0 };

    var server = tcp.ServerStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer server.deinit();

    var client = tcp.ClientStateMachine(TestStream.Writer).init(std.testing.allocator, stream.writer());
    defer client.deinit();

    try testDefaultCryptoHandshake(&server, &client, &stream);

    try testCommonHandshake(&server, &client, &stream, .many, .one);
}

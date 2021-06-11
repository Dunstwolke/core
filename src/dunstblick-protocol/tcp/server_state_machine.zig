//! This file implements a dunstblick protocol display client.
//! It does not depend on any network interface, but has a pure push/pull API
//! that allows using it in any freestanding environment.
//!
//! Design considerations:
//! Dunstblick application servers can be embedded types, thus this state machine is implemented
//! with tight memory requirement in mind. It tries not to create unnecessary copies or allocate memory.

const std = @import("std");
const zig_charm = @import("charm");
const shared_types = @import("shared_types.zig");
const types = @import("../data-types.zig");
const protocol = @import("v1.zig");

const CryptoState = @import("CryptoState.zig");

pub const ReceiveData = struct {
    consumed: usize,
    event: ?ReceiveEvent,

    fn notEnough(len: usize) @This() {
        return .{
            .consumed = len,
            .event = null,
        };
    }

    fn createEvent(consumed: usize, event: ReceiveEvent) @This() {
        return @This(){
            .consumed = consumed,
            .event = event,
        };
    }
};

pub const ReceiveEvent = union(enum) {
    initiate_handshake: InitiateHandshake,
    authenticate_info: AuthenticateInfo,
    connect_header: ConnectHeader,
    resource_request: ResourceRequest,
    message: []const u8,

    const InitiateHandshake = struct {
        has_username: bool,
        has_password: bool,
    };
    const AuthenticateInfo = struct {
        /// If not null, the user has provided a user name
        username: ?[]const u8,

        /// When `true`, a key must now be provided via 
        /// the `setKeyAndVerify()` method.
        requires_key: bool,
    };
    const ConnectHeader = struct {
        capabilities: protocol.ClientCapabilities,
        screen_width: u16,
        screen_height: u16,
    };
    const ResourceRequest = struct {
        requested_resources: []const types.ResourceID,
    };
};

pub const AuthAction = enum {
    /// The server waits for authentication informationen.
    /// Provide more data from the client.
    expect_auth_info,

    /// The server does not expend authentication information,
    /// just invoke `sendAuthenticationResult()`
    send_auth_result,

    /// Drop the connection, the authentication would fail anyways (server does not expect what client sends)
    drop,
};

pub const AuthenticationResult = enum {
    failure,
    success,
};

pub fn ServerStateMachine(comptime Writer: type) type {
    return struct {
        const Self = @This();

        pub const SendError = Writer.Error || error{
            /// A necessary allocation couldn't be performed.
            OutOfMemory,
            /// A slice contained too many elements
            SliceOutOfRange,
        };

        pub const ReceiveError = error{
            /// A necessary allocation couldn't be performed.
            OutOfMemory,
            /// The other peer sent data when it was not expected
            UnexpectedData,
            /// The other peer sent data that could be identified as invalid
            InvalidData,
            /// The other peer tried to connect with an unsupported version
            UnsupportedVersion,
            /// The other peer violated protocol constrains,
            ProtocolViolation,
        };

        allocator: *std.mem.Allocator,
        writer: Writer,

        /// The cryptographic provider for the connection.
        crypto: CryptoState,

        auth_token: ?CryptoState.Hash = null,

        receive_buffer: shared_types.MsgReceiveBuffer = .{},
        temp_msg_buffer: std.ArrayListUnmanaged(u8) = .{},

        state: shared_types.State = .initiate_handshake,

        /// Number of resources that are available on the server
        available_resource_count: u32 = undefined,

        /// Number of resources that are requested by the client.
        requested_resource_count: u32 = undefined,

        will_receive_username: bool = false,
        will_receive_password: bool = false,

        pub fn init(allocator: *std.mem.Allocator, writer: Writer) Self {
            return Self{
                .allocator = allocator,
                .writer = writer,
                .crypto = CryptoState.init(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.receive_buffer.deinit(self.allocator);
            self.temp_msg_buffer.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn isFaulted(self: Self) bool {
            return (self.state == .faulted);
        }

        pub fn isConnectionEstablished(self: Self) bool {
            return (self.state == .established);
        }

        pub fn setKeyAndVerify(self: *Self, key: CryptoState.Key) AuthenticationResult {
            std.debug.assert(self.auth_token != null);
            const sent_auth_token = self.auth_token.?;

            const valid_auth_token = self.crypto.start(key, .server);

            const auth_valid = std.mem.eql(u8, &sent_auth_token, &valid_auth_token);

            if (auth_valid) {
                return AuthenticationResult.success;
            } else {
                // This would be the correct thing here, but we still need to be able to send the
                // correct message back to the client
                //                self.state = .faulted;
                return AuthenticationResult.failure;
            }
        }

        /// Strips the tag from the payload and decrypts the message if necessary.
        fn decrypt(self: *Self, data: []u8) ![]u8 {
            if (self.crypto.encryption_enabled) {
                const payload = data[0 .. data.len - 16];
                const tag = data[data.len - 16 ..][0..16];
                try self.crypto.decrypt(tag.*, payload);
                return payload;
            } else {
                return data;
            }
        }

        fn decryptAndGet(self: *Self, info: shared_types.ConsumeResult.Info, comptime T: type) !*align(1) T {
            const data = try self.decrypt(info.data);
            std.debug.assert(data.len == @sizeOf(T));
            return std.mem.bytesAsValue(T, data[0..@sizeOf(T)]);
        }

        pub fn pushData(self: *Self, new_data: []const u8) ReceiveError!ReceiveData {
            const expected_additional_len = if (self.crypto.encryption_enabled)
                @as(usize, 16)
            else
                @as(usize, 0);

            switch (self.state) {
                .initiate_handshake => {
                    switch (try self.receive_buffer.pushData(self.allocator, new_data, expected_additional_len + @sizeOf(protocol.InitiateHandshake))) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |info| {
                            const value = try self.decryptAndGet(info, protocol.InitiateHandshake);

                            if (!std.mem.eql(u8, &value.magic, &protocol.magic))
                                return error.UnexpectedData;
                            if (value.protocol_version != protocol.protocol_version)
                                return error.UnsupportedVersion;

                            self.crypto.client_nonce = value.client_nonce;
                            self.will_receive_username = value.flags.has_username;
                            self.will_receive_password = value.flags.has_password;

                            self.state = .acknowledge_handshake;
                            return ReceiveData.createEvent(
                                info.consumed,
                                ReceiveEvent{
                                    .initiate_handshake = .{
                                        .has_username = value.flags.has_username,
                                        .has_password = value.flags.has_password,
                                    },
                                },
                            );
                        },
                    }
                },
                .acknowledge_handshake => return error.UnexpectedData,
                .authenticate_info => {
                    var total_len: usize = 0;
                    if (self.will_receive_username)
                        total_len += 32;
                    if (self.will_receive_password)
                        total_len += 32;

                    switch (try self.receive_buffer.pushData(self.allocator, new_data, expected_additional_len + total_len)) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |info| {
                            var buffer = try self.decrypt(info.data);
                            var offset: usize = 0;

                            var username = if (self.will_receive_username) blk: {
                                defer offset += 32;
                                break :blk std.mem.sliceTo(buffer[offset..][0..32], 0);
                            } else null;

                            self.auth_token = if (self.will_receive_password) blk: {
                                defer offset += 32;
                                break :blk buffer[offset..][0..32].*;
                            } else null;

                            self.state = .authenticate_result;

                            return ReceiveData.createEvent(
                                info.consumed,
                                ReceiveEvent{
                                    .authenticate_info = .{
                                        .username = username,
                                        .requires_key = (self.auth_token != null),
                                    },
                                },
                            );
                        },
                    }
                },
                .authenticate_result => return error.UnexpectedData,
                .connect_header => {
                    switch (try self.receive_buffer.pushData(self.allocator, new_data, expected_additional_len + @sizeOf(protocol.ConnectHeader))) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |info| {
                            const value = try self.decryptAndGet(info, protocol.ConnectHeader);

                            self.state = .connect_response;

                            return ReceiveData.createEvent(
                                info.consumed,
                                ReceiveEvent{
                                    .connect_header = .{
                                        .capabilities = value.capabilities,
                                        .screen_width = value.screen_width,
                                        .screen_height = value.screen_height,
                                    },
                                },
                            );
                        },
                    }
                },
                .connect_response => return error.UnexpectedData,
                .connect_response_item => return error.UnexpectedData,
                .resource_request => {
                    switch (try self.receive_buffer.pushPrefix(self.allocator, new_data, 4)) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |prefix_info| {
                            // prefix_info.consumed
                            const len = std.mem.readIntLittle(u32, prefix_info.data[0..4]);

                            const total_len = @sizeOf(u32) + @sizeOf(types.ResourceID) * len;

                            switch (try self.receive_buffer.pushData(self.allocator, new_data[prefix_info.consumed..], expected_additional_len + total_len)) {
                                .need_more => return ReceiveData.notEnough(new_data.len),
                                .ok => |info| {
                                    const data = try self.decrypt(info.data[4..]);

                                    const resources = @alignCast(4, std.mem.bytesAsSlice(types.ResourceID, data));
                                    std.debug.assert(resources.len == len);

                                    self.requested_resource_count = len;
                                    if (self.requested_resource_count > 0) {
                                        self.state = .{ .resource_header = 0 };
                                    } else {
                                        self.state = .established;
                                    }

                                    return ReceiveData.createEvent(
                                        prefix_info.consumed + info.consumed,
                                        ReceiveEvent{
                                            .resource_request = .{
                                                .requested_resources = resources,
                                            },
                                        },
                                    );
                                },
                            }
                        },
                    }
                },
                .resource_header => return error.UnexpectedData,
                .established => {
                    switch (try self.receive_buffer.pushPrefix(self.allocator, new_data, 4)) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |prefix_info| {
                            // prefix_info.consumed
                            const len = std.mem.readIntLittle(u32, prefix_info.data[0..4]);

                            const total_len = @sizeOf(u32) + len;

                            switch (try self.receive_buffer.pushData(self.allocator, new_data[prefix_info.consumed..], expected_additional_len + total_len)) {
                                .need_more => return ReceiveData.notEnough(new_data.len),
                                .ok => |info| {
                                    const data = try self.decrypt(info.data[4..]);

                                    return ReceiveData.createEvent(
                                        prefix_info.consumed + info.consumed,
                                        ReceiveEvent{ .message = data },
                                    );
                                },
                            }
                        },
                    }
                },
                .faulted => return error.UnexpectedData,
            }
        }

        /// Writes raw data to the stream.
        fn sendRaw(self: *Self, data: []const u8) SendError!void {
            try self.writer.writeAll(data);
        }

        /// Writes a blob of data to the stream and encrypts it if required.
        /// This will also send the necessary tag.
        fn send(self: *Self, data: []u8) SendError!void {
            if (self.crypto.encryption_enabled) {
                const tag = self.crypto.encrypt(data);
                try self.sendRaw(data);
                try self.sendRaw(&tag);
            } else {
                try self.sendRaw(data);
            }
        }

        pub fn acknowledgeHandshake(self: *Self, response: protocol.AcknowledgeHandshake.Response) SendError!AuthAction {
            std.debug.assert(self.state == .acknowledge_handshake);

            // "reject" is only allowed when a name/password will actually be sent
            std.debug.assert(!response.rejects_username or self.will_receive_username);
            std.debug.assert(!response.rejects_password or self.will_receive_password);

            // "require" must only be set when no name/password was sent
            std.debug.assert(!response.requires_username or !self.will_receive_username);
            std.debug.assert(!response.requires_password or !self.will_receive_password);

            var bits = protocol.AcknowledgeHandshake{
                .response = response,
                .server_nonce = self.crypto.server_nonce,
            };

            try self.send(std.mem.asBytes(&bits));

            if (response.rejects_username or
                response.rejects_password or
                response.requires_username or
                response.requires_password)
            {
                self.state = .faulted;
                return .drop;
            } else {
                if (self.will_receive_username or self.will_receive_password) {
                    self.state = .authenticate_info;
                    return .expect_auth_info;
                } else {
                    self.state = .authenticate_result;
                    return .send_auth_result;
                }
            }
        }

        pub fn sendAuthenticationResult(self: *Self, result: protocol.AuthenticationResult.Result, encrypt_transport: bool) SendError!void {
            std.debug.assert(self.state == .authenticate_result);

            // Encryption is only allowed when a password was provided
            std.debug.assert(!encrypt_transport or self.will_receive_password);

            var bits = protocol.AuthenticationResult{
                .result = result,
                .flags = .{
                    .encrypted = encrypt_transport,
                },
            };

            try self.send(std.mem.asBytes(&bits));

            // After this, crypto handshake is done, we can now successfully
            // encrypt our messages if wanted
            self.crypto.encryption_enabled = encrypt_transport;

            if (result == .success) {
                self.state = .connect_header;
            } else {
                self.state = .faulted;
            }
        }

        pub fn sendConnectResponse(self: *Self, resources: []const protocol.ConnectResponseItem) SendError!void {
            std.debug.assert(self.state == .connect_response);

            var bits = protocol.ConnectResponse{
                .resource_count = std.math.cast(u32, resources.len) catch return error.SliceOutOfRange,
            };

            try self.send(std.mem.asBytes(&bits));

            for (resources) |descriptor| {
                var clone = descriptor;
                try self.send(std.mem.asBytes(&clone));
            }

            self.available_resource_count = bits.resource_count;
            if (self.available_resource_count == 0) {
                self.state = .established;
            } else {
                self.state = .resource_request;
            }
        }

        pub fn sendResourceHeader(self: *Self, id: types.ResourceID, data: []const u8) SendError!void {
            std.debug.assert(self.state == .resource_header);
            std.debug.assert(self.state.resource_header < self.available_resource_count);

            var length_data: [4]u8 = undefined;
            std.mem.writeIntLittle(u32, &length_data, std.math.cast(u32, data.len) catch return error.SliceOutOfRange);

            var bits = protocol.ResourceHeader{
                .id = id,
            };

            const header_len = @sizeOf(protocol.ResourceHeader);

            self.temp_msg_buffer.shrinkRetainingCapacity(0);
            try self.temp_msg_buffer.resize(self.allocator, header_len + data.len);

            std.mem.copy(u8, self.temp_msg_buffer.items, std.mem.asBytes(&bits));
            std.mem.copy(u8, self.temp_msg_buffer.items[header_len..], data);

            try self.sendRaw(&length_data); // must be unencrypted data!
            try self.send(self.temp_msg_buffer.items);

            self.state.resource_header += 1;
            if (self.state.resource_header == self.requested_resource_count) {
                self.state = .established;
            }
        }

        pub fn sendMessage(self: *Self, message: []const u8) SendError!void {
            std.debug.assert(self.state == .established);

            var length_data: [4]u8 = undefined;
            std.mem.writeIntLittle(u32, &length_data, std.math.cast(u32, message.len) catch return error.SliceOutOfRange);

            try self.temp_msg_buffer.resize(self.allocator, message.len);
            std.mem.copy(u8, self.temp_msg_buffer.items, message);

            try self.sendRaw(&length_data); // must be unencrypted data!
            try self.send(self.temp_msg_buffer.items);
        }
    };
}

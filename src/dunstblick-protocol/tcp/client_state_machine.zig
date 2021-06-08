//! This file implements a dunstblick protocol display client.
//! It does not depend on any network interface, but has a pure push/pull API
//! that allows using it in any freestanding environment.
//! 
//! Design considerations:
//! Display clients have higher requirements on the hardware and assume to have
//! at least memory in the mega bytes available, thus require a general purpose
//! allocator.

const std = @import("std");
const protocol = @import("v1.zig");
const types = @import("../data-types.zig");
const shared_types = @import("shared_types.zig");

const CryptoState = @import("CryptoState.zig");

pub const ReceiveError = error{
    OutOfMemory,
    UnexpectedData,
    UnsupportedVersion,
    ProtocolViolation,
};

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
    acknowledge_handshake: AcknowledgeHandshake,
    authenticate_result: AuthenticateResult,
    connect_response: ConnectResponse,
    connect_response_item: protocol.ConnectResponseItem,
    resource_header: ResourceHeader,
    message: []const u8,

    const AcknowledgeHandshake = struct {
        requires_username: bool,
        requires_password: bool,
        rejects_username: bool,
        rejects_password: bool,

        pub fn ok(self: @This()) bool {
            return !self.requires_password;
        }
    };
    const AuthenticateResult = struct {
        result: protocol.AuthenticationResult.Result,
    };
    const ConnectResponse = struct {
        resource_count: u32,
    };
    const ResourceHeader = struct {
        resource_id: types.ResourceID,
        data: []const u8,
    };
};

pub fn ClientStateMachine(comptime Writer: type) type {
    return struct {
        const Self = @This();

        pub const SendError = Writer.Error || error{
            /// A necessary allocation couldn't be performed.
            OutOfMemory,
            /// A slice contained too many elements
            SliceOutOfRange,
        };

        allocator: *std.mem.Allocator,

        crypto: CryptoState,

        state: shared_types.State = .initiate_handshake,

        username: ?[32]u8 = null,
        password: ?CryptoState.Key = null,

        temp_msg_buffer: std.ArrayListUnmanaged(u8) = .{},
        receive_buffer: shared_types.MsgReceiveBuffer = .{},

        writer: Writer,

        /// Number of resources that are available on the server
        available_resource_count: u32 = undefined,

        /// Number of resources that are requested by the client.
        requested_resource_count: u32 = undefined,

        pub fn init(allocator: *std.mem.Allocator, writer: Writer) Self {
            return Self{
                .allocator = allocator,
                .writer = writer,
                .crypto = CryptoState.init(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.temp_msg_buffer.deinit(self.allocator);
            self.receive_buffer.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn isFaulted(self: Self) bool {
            return (self.state == .faulted);
        }

        pub fn pushData(self: *Self, new_data: []const u8) ReceiveError!ReceiveData {
            switch (self.state) {
                .initiate_handshake => return error.UnexpectedData,
                .acknowledge_handshake => {
                    switch (try self.receive_buffer.pushData(self.allocator, new_data, @sizeOf(protocol.AcknowledgeHandshake))) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |info| {
                            const value = info.get(protocol.AcknowledgeHandshake);

                            self.crypto.server_nonce = value.server_nonce;

                            const response = ReceiveData.createEvent(
                                info.consumed,
                                .{ .acknowledge_handshake = ReceiveEvent.AcknowledgeHandshake{
                                    .requires_username = value.response.requires_username,
                                    .requires_password = value.response.requires_password,
                                    .rejects_username = value.response.rejects_username,
                                    .rejects_password = value.response.rejects_password,
                                } },
                            );

                            if (response.event.?.acknowledge_handshake.ok()) {
                                if (self.username != null or self.password != null) {
                                    self.state = .authenticate_info;
                                } else {
                                    self.state = .authenticate_result;
                                }
                            } else {
                                self.state = .faulted;
                            }
                            return response;
                        },
                    }
                },
                .authenticate_info => return error.UnexpectedData,
                .authenticate_result => {
                    switch (try self.receive_buffer.pushData(self.allocator, new_data, @sizeOf(protocol.AuthenticationResult))) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |info| {
                            const value = info.get(protocol.AuthenticationResult);

                            if (self.password == null and value.flags.encrypted) {
                                self.state = .faulted;
                                return error.ProtocolViolation;
                            }

                            self.state = .connect_header;
                            return ReceiveData.createEvent(
                                info.consumed,
                                ReceiveEvent{ .authenticate_result = .{ .result = value.result } },
                            );
                        },
                    }
                },
                .connect_header => return error.UnexpectedData,
                .connect_response => {
                    switch (try self.receive_buffer.pushData(self.allocator, new_data, @sizeOf(protocol.ConnectResponse))) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |info| {
                            const value = info.get(protocol.ConnectResponse);

                            self.available_resource_count = value.resource_count;
                            self.state = .{ .connect_response_item = 0 };

                            return ReceiveData.createEvent(
                                info.consumed,
                                ReceiveEvent{ .connect_response = ReceiveEvent.ConnectResponse{
                                    .resource_count = value.resource_count,
                                } },
                            );
                        },
                    }
                },
                .connect_response_item => |*current_index| {
                    switch (try self.receive_buffer.pushData(self.allocator, new_data, @sizeOf(protocol.ConnectResponseItem))) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |info| {
                            const value = info.get(protocol.ConnectResponseItem);

                            current_index.* += 1;
                            if (current_index.* >= self.available_resource_count) {
                                self.state = .resource_request;
                            }

                            return ReceiveData.createEvent(
                                info.consumed,
                                ReceiveEvent{ .connect_response_item = value.* },
                            );
                        },
                    }
                },
                .resource_request => return error.UnexpectedData,
                .resource_header => |*current_index| {
                    switch (try self.receive_buffer.pushPrefix(self.allocator, new_data, 4)) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |prefix_info| {
                            // prefix_info.consumed
                            const len = std.mem.readIntLittle(u32, prefix_info.data[0..4]);

                            const total_len = @sizeOf(u32) + @sizeOf(types.ResourceID) + len;

                            switch (try self.receive_buffer.pushData(self.allocator, new_data[prefix_info.consumed..], total_len)) {
                                .need_more => return ReceiveData.notEnough(new_data.len - prefix_info.consumed),
                                .ok => |info| {
                                    const resource_id = @intToEnum(types.ResourceID, std.mem.readIntLittle(u32, info.data[4..8]));

                                    current_index.* += 1;
                                    if (current_index.* >= self.requested_resource_count) {
                                        self.state = .established;
                                    }

                                    return ReceiveData.createEvent(
                                        prefix_info.consumed + info.consumed,
                                        ReceiveEvent{
                                            .resource_header = .{
                                                .resource_id = resource_id,
                                                .data = info.data[8..],
                                            },
                                        },
                                    );
                                },
                            }
                        },
                    }
                },
                .established => {
                    switch (try self.receive_buffer.pushPrefix(self.allocator, new_data, 4)) {
                        .need_more => return ReceiveData.notEnough(new_data.len),
                        .ok => |prefix_info| {
                            // prefix_info.consumed
                            const len = std.mem.readIntLittle(u32, prefix_info.data[0..4]);

                            const total_len = @sizeOf(u32) + len;

                            switch (try self.receive_buffer.pushData(self.allocator, new_data[prefix_info.consumed..], total_len)) {
                                .need_more => return ReceiveData.notEnough(new_data.len - prefix_info.consumed),
                                .ok => |info| {
                                    return ReceiveData.createEvent(
                                        prefix_info.consumed + info.consumed,
                                        ReceiveEvent{ .message = info.data[4..] },
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

        pub fn initiateHandshake(self: *Self, username: ?[]const u8, password: ?[]const u8) SendError!void {
            std.debug.assert(self.state == .initiate_handshake);
            if (username) |name| {
                if (name.len > 32)
                    return error.SliceOutOfRange;
                var buf: [32]u8 = [1]u8{0} ** 32;
                std.mem.copy(u8, &buf, name);
                if (std.builtin.mode == .Debug) {
                    for (buf[name.len..]) |c| {
                        std.debug.assert(c == 0);
                    }
                }
                self.username = buf;
            }

            if (password) |passwd| {
                self.password = CryptoState.hashPassword(passwd, username orelse "static server");
            }

            var handshake = protocol.InitiateHandshake{
                .client_nonce = self.crypto.client_nonce,
                .flags = .{
                    .has_username = (username != null),
                    .has_password = (password != null),
                },
            };

            try self.send(std.mem.asBytes(&handshake));
            self.state = .acknowledge_handshake;
        }

        pub fn sendAuthenticationInfo(self: *Self) SendError!void {
            std.debug.assert(self.state == .authenticate_info);

            var buffer: [64]u8 = undefined;

            var offset: usize = 0;
            if (self.username) |username| {
                std.mem.copy(u8, buffer[offset..][0..32], &username);
                offset += 32;
            }
            if (self.password) |password| {
                std.mem.copy(u8, buffer[offset..][0..password.len], &password);
                offset += password.len;
            }

            try self.send(buffer[0..offset]);

            self.state = .authenticate_result;
        }

        pub fn sendConnectHeader(self: *Self, screen_width: u16, screen_height: u16, capabilities: protocol.ClientCapabilities) SendError!void {
            std.debug.assert(self.state == .connect_header);

            var header = protocol.ConnectHeader{
                .screen_width = screen_width,
                .screen_height = screen_height,
                .capabilities = capabilities,
            };
            try self.send(std.mem.asBytes(&header));

            self.state = .connect_response;
        }

        pub fn sendResourceRequest(self: *Self, resources: []const types.ResourceID) !void {
            std.debug.assert(self.state == .resource_request);

            var length_data: [4]u8 = undefined;
            std.mem.writeIntLittle(u32, &length_data, std.math.cast(u32, resources.len) catch return error.SliceOutOfRange);

            self.temp_msg_buffer.shrinkRetainingCapacity(0);

            try self.temp_msg_buffer.resize(self.allocator, resources.len * @sizeOf(types.ResourceID));
            std.mem.copy(
                types.ResourceID,
                @alignCast(@alignOf(types.ResourceID), std.mem.bytesAsSlice(types.ResourceID, self.temp_msg_buffer.items)),
                resources,
            );

            try self.sendRaw(&length_data); // must be unencrypted data!
            try self.send(self.temp_msg_buffer.items);

            self.requested_resource_count = @truncate(u32, resources.len);
            self.state = .{ .resource_header = 0 };
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

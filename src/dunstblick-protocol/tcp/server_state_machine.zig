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
        //
    };
    const ConnectHeader = struct {
        //
    };
    const ResourceRequest = struct {
        //
    };
};

pub const AuthAction = enum {
    expect_auth_info,
    send_auth_result,
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
            OutOfMemory,
            UnexpectedData,
            UnsupportedVersion,
        };

        allocator: *std.mem.Allocator,
        writer: Writer,

        /// The cryptographic provider for the connection.
        crypto: CryptoState,

        /// When this is `true`, the packages will be encrypted/decrypted with `charm`.
        crpyto_enabled: bool = false,

        receive_buffer: std.ArrayListUnmanaged(u8) = .{},
        temp_msg_buffer: std.ArrayListUnmanaged(u8) = .{},

        state: shared_types.State = .initiate_handshake,

        expects_password: bool = false,
        expects_username: bool = false,

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
            self.* = undefined;
        }

        const ConsumeResult = union(enum) {
            not_enough: ReceiveData,
            fits: Info,

            const Info = struct {
                consumed: usize,
                data: []u8,
            };
        };
        fn consumeData(self: *Self, new_data: []const u8, expected_size: usize) !ConsumeResult {
            const old_len = self.receive_buffer.items.len;
            if (old_len + new_data.len < expected_size)
                return ConsumeResult{ .not_enough = ReceiveData.notEnough(new_data.len) };
            const consumed = new_data.len - ((new_data.len + old_len) - expected_size);

            try self.receive_buffer.appendSlice(self.allocator, new_data[0..consumed]);

            return ConsumeResult{
                .fits = .{
                    .consumed = consumed,
                    .data = self.receive_buffer.items[0..expected_size],
                },
            };
        }

        pub fn pushData(self: *Self, new_data: []const u8) ReceiveError!ReceiveData {
            const old_data = self.receive_buffer.items;

            switch (self.state) {
                .initiate_handshake => {
                    switch (try self.consumeData(new_data, @sizeOf(protocol.InitiateHandshake))) {
                        .not_enough => |v| return v,
                        .fits => |info| {
                            defer self.receive_buffer.shrinkRetainingCapacity(0);

                            const value = std.mem.bytesAsValue(protocol.InitiateHandshake, info.data[0..@sizeOf(protocol.InitiateHandshake)]);

                            if (!std.mem.eql(u8, &value.magic, &protocol.magic))
                                return error.UnexpectedData;
                            if (value.protocol_version != protocol.protocol_version)
                                return error.UnsupportedVersion;

                            self.crypto.client_nonce = value.client_nonce;
                            self.will_receive_username = value.flags.has_username;
                            self.will_receive_password = value.flags.has_password;

                            self.state = .acknowledge_handshake;
                            return ReceiveData{
                                .consumed = info.consumed,
                                .event = ReceiveEvent{
                                    .initiate_handshake = .{
                                        .has_username = value.flags.has_username,
                                        .has_password = value.flags.has_password,
                                    },
                                },
                            };
                        },
                    }
                },
                .acknowledge_handshake => return error.UnexpectedData,
                .authenticate_info => @panic("not implemented yet"),
                .authenticate_result => return error.UnexpectedData,
                .connect_header => @panic("not implemented yet"),
                .connect_response => return error.UnexpectedData,
                .connect_response_item => return error.UnexpectedData,
                .resource_request => @panic("not implemented yet"),
                .resource_header => return error.UnexpectedData,
                .established => @panic("not implemented yet"),
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
            std.debug.assert(!response.requires_username or self.will_receive_username);
            std.debug.assert(!response.requires_password or self.will_receive_password);

            var bits = protocol.AcknowledgeHandshake{
                .response = response,
                .server_nonce = self.crypto.server_nonce,
            };

            try self.send(std.mem.asBytes(&bits));

            if (self.will_receive_username or self.will_receive_password) {
                self.state = .authenticate_info;
                return .expect_auth_info;
            } else {
                self.state = .authenticate_result;
                return .send_auth_result;
            }
        }
    };
}

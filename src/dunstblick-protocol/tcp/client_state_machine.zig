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

        writer: Writer,

        pub fn init(allocator: *std.mem.Allocator, writer: Writer) Self {
            return Self{
                .allocator = allocator,
                .writer = writer,
                .crypto = CryptoState.init(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.temp_msg_buffer.deinit(self.allocator);
            self.* = undefined;
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

            try self.send(&buffer[0..offset]);

            self.state = .authenticate_result;
        }

        pub fn sendConnectHeader(self: *Self, screen_width: u16, screen_height: u16, capabilities: protocol.ClientCapabilities) SendError!void {
            std.debug.assert(self.state == .connect_header);

            var header = protocol.ConnectHeader{
                .screen_size_x = screen_width,
                .screen_size_y = screen_height,
                .capabilities = capabilities,
            };
            try self.send(std.mem.asBytes(&header));

            self.state = .connect_response;
        }

        pub fn sendResourceRequest(self: *Self, resources: []const types.ResourceID) !void {
            std.debug.assert(self.state == .resource_request);

            const count = std.math.cast(u32, resources.len) catch return error.SliceOutOfRange;

            var request = protocol.ResourceRequest{
                .resource_count = count,
            };

            self.temp_msg_buffer.shrinkRetainingCapacity(0);

            var writer = self.temp_msg_buffer.writer();
            try writer.writeIntLittle(u32, count);
            for (resources) |id| {
                try writer.writeIntLittle(u32, @enumToInt(id));
            }

            try self.send(self.temp_msg_buffer.items);

            self.state = .resource_header;
        }

        pub fn sendMessage(self: *Self, message: []const u8) SendError!void {
            std.debug.assert(self.state == .established);

            const length = std.math.cast(u32, message.len) catch return error.SliceOutOfRange;

            var msg_length_buffer: [4]u8 = undefined;
            std.mem.writeIntLittle(u32, &msg_length_buffer, length);

            if (self.crypto.encryption_enabled) {
                try self.temp_msg_buffer.resize(message.len);
                std.mem.copy(u8, self.temp_msg_buffer.items, message);

                try self.sendRaw(&msg_length_buffer);
                const tag = self.crypto.encrypt(self.temp_msg_buffer.items);
                try self.sendRaw(self.temp_msg_buffer.items);
                try self.sendRaw(&tag);
            } else {
                try self.sendRaw(&msg_length_buffer);
                try self.sendRaw(message);
            }
        }
    };
}

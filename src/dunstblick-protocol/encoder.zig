const std = @import("std");
const builtin = @import("builtin");

usingnamespace @import("data-types.zig");

const ZigZagInt = @import("zigzagint.zig");

pub fn Encoder(comptime Stream: type) type {
    return struct {
        const Self = @This();

        stream: Stream,

        pub fn init(stream: Stream) Self {
            return Self{
                .stream = stream,
            };
        }

        pub fn writeByte(self: *Self, byte: u8) !void {
            try self.stream.writeByte(byte);
        }

        pub fn writeRaw(self: *Self, data: []const u8) !void {
            try self.stream.writeAll(data);
        }

        pub fn writeEnum(self: *Self, e: u8) !void {
            try self.writeByte(e);
        }

        pub fn writeID(self: *Self, id: u32) !void {
            try self.writeVarUInt(id);
        }

        pub fn writeString(self: *Self, string: []const u8) !void {
            try self.writeVarUInt(@intCast(u32, string.len));
            try self.writeRaw(string);
        }

        pub fn writeNumber(self: *Self, number: f32) !void {
            std.debug.assert(builtin.target.cpu.arch.endian() == .Little);
            try self.writeRaw(std.mem.asBytes(&number));
        }

        pub fn writeVarUInt(self: *Self, value: u32) !void {
            var buf: [5]u8 = undefined;

            var maxidx: usize = 4;

            comptime var n: usize = 0;
            inline while (n < 5) : (n += 1) {
                const chr = &buf[4 - n];
                chr.* = @truncate(u8, (value >> (7 * n)) & 0x7F);
                if (chr.* != 0)
                    maxidx = 4 - n;
                if (n > 0)
                    chr.* |= 0x80;
            }

            std.debug.assert(maxidx < 5);
            try self.writeRaw(buf[maxidx..]);
        }

        pub fn writeVarSInt(self: *Self, value: i32) !void {
            try self.writeVarUInt(ZigZagInt.encode(value));
        }
    };
}

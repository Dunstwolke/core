const std = @import("std");

usingnamespace @import("data-types.zig");

const ZigZagInt = @import("zigzagint.zig");

pub const Decoder = struct {
    const Self = @This();

    source: []const u8,
    offset: usize,

    pub fn init(data: []const u8) Self {
        return Self{
            .source = data,
            .offset = 0,
        };
    }

    pub fn readByte(self: *Self) !u8 {
        if (self.offset >= self.source.len)
            return error.EndOfStream;
        const value = self.source[self.offset];
        self.offset += 1;
        return value;
    }

    pub fn readEnum(self: *Self, comptime T: type) !T {
        if (@typeInfo(T) != .Enum) @compileError("T must be a enum type!");

        const I = std.meta.Tag(T);
        switch (I) {
            u8 => {
                const byte = try self.readByte();
                return std.meta.intToEnum(T, byte);
            },
            u32 => {
                const int = try self.readVarUInt();
                return std.meta.intToEnum(T, int);
            },
            else => @compileError(@typeName(I) ++ " is not a supported enumeration tag type!"),
        }
    }

    pub fn readVarUInt(self: *Self) !u32 {
        var number: u32 = 0;

        while (true) {
            const value = try self.readByte();
            number <<= 7;
            number |= value & 0x7F;
            if ((value & 0x80) == 0)
                break;
        }

        return number;
    }

    pub fn readVarSInt(self: *Self) !i32 {
        return ZigZagInt.decode(try self.readVarUInt());
    }

    pub fn readRaw(self: *Self, n: usize) ![]const u8 {
        if (self.offset + n > self.source.len)
            return error.EndOfStream;
        const value = self.source[self.offset .. self.offset + n];
        self.offset += n;
        return value;
    }

    pub fn readToEnd(self: *Self) ![]const u8 {
        if (self.offset >= self.source.len)
            return &[0]u8{};
        const value = self.source[self.offset..];
        self.offset = self.source.len;
        return value;
    }

    pub fn readNumber(self: *Self) !f32 {
        const bits = try self.readRaw(4);
        return @bitCast(f32, bits[0..4].*);
    }
    pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        const len = try self.readVarUInt();

        const str = try allocator.alloc(u8, len);
        errdefer allocator.free(str);

        std.mem.copy(u8, str, try self.readRaw(len));

        return str;
    }
};

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

    pub fn readValue(self: *Self, value_type: Type, allocator: ?*std.mem.Allocator) !Value {
        var value = Value{
            .type = value_type,
            .value = undefined,
        };
        const val = &value.value;
        switch (value_type) {
            .enumeration => val.enumeration = try self.readByte(),

            .integer => val.integer = try self.readVarSInt(),

            .resource => val.resource = @intToEnum(ResourceID, try self.readVarUInt()),

            .object => val.object = @intToEnum(ObjectID, try self.readVarUInt()),

            .number => val.number = try self.readNumber(),

            .boolean => val.boolean = ((try self.readByte()) != 0),

            .color => {
                val.color.red = try self.readByte();
                val.color.green = try self.readByte();
                val.color.blue = try self.readByte();
                val.color.alpha = try self.readByte();
            },

            .size => {
                val.size.width = try self.readVarUInt();
                val.size.height = try self.readVarUInt();
            },

            .point => {
                val.point.x = try self.readVarSInt();
                val.point.y = try self.readVarSInt();
            },

            // HOW?
            .string => {
                if (allocator) |allo| {
                    const strlen = try self.readVarUInt();

                    const str = try allo.allocWithOptions(u8, strlen, null, 0);
                    errdefer allo.free(str);

                    std.mem.copy(
                        u8,
                        str[0..],
                        try self.readRaw(strlen),
                    );

                    val.string = str.ptr;
                } else {
                    return error.NotSupported; // not implemented yet
                }
            },

            .margins => {
                val.margins.left = try self.readVarUInt();
                val.margins.top = try self.readVarUInt();
                val.margins.right = try self.readVarUInt();
                val.margins.bottom = try self.readVarUInt();
            },

            .objectlist => std.log.err("Reading objectlist property not possible yet.", .{}),

            .event => val.event = @intToEnum(EventID, try self.readVarUInt()),

            .name => val.name = @intToEnum(WidgetName, try self.readVarUInt()),

            .sizelist => return error.NotSupported,
        }
        return value;
    }

    pub fn deinitValue(self: Self, value: Value, allocator: *std.mem.Allocator) void {
        if (value.type == .string) {
            allocator.free(std.mem.spanZ(value.value.string));
        }
    }
};

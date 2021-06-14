const std = @import("std");
const protocol = @import("dunstblick-protocol");

const logger = std.log.scoped(.dunstblick_value);

const types = @import("types.zig");

const String = types.String;
const ObjectList = types.ObjectList;
const SizeList = types.SizeList;

pub const Value = union(enum) {
    integer: i32,
    number: f32,
    string: String,
    enumeration: u8,
    margins: protocol.Margins,
    color: protocol.Color,
    size: protocol.Size,
    point: protocol.Point,
    resource: protocol.ResourceID,
    boolean: bool,
    object: protocol.ObjectID,
    objectlist: ObjectList,
    sizelist: SizeList,
    event: protocol.EventID,
    name: protocol.WidgetName,

    pub fn deinit(self: *Value) void {
        switch (self.*) {
            .string => |*list| list.deinit(),
            .objectlist => |*list| list.deinit(),
            .sizelist => |*list| list.deinit(),
            else => {},
        }
        self.* = undefined;
    }

    pub fn convertTo(self: Value, comptime T: type) !T {
        if (self.get(T)) |v| {
            return v;
        } else |err| {
            // we ignore the conversion error, we just want to short-cut
            // the conversion path when a compatible type is queried.
        }

        const ti = @typeInfo(T);

        switch (self) {
            .integer => |val| return error.UnsupportedConversion,
            .number => |val| return error.UnsupportedConversion,
            .string => |val| return error.UnsupportedConversion,
            .margins => |val| return error.UnsupportedConversion,
            .color => |val| return error.UnsupportedConversion,
            .size => |val| return error.UnsupportedConversion,
            .point => |val| return error.UnsupportedConversion,

            .boolean => |val| {
                if (ti == .Int)
                    return if (val) @as(u1, 1) else @as(u1, 0);
                if (T == f16)
                    return if (val) @as(f16, 1) else @as(f16, 0);
                if (T == f32)
                    return if (val) @as(f32, 1) else @as(f32, 0);
                if (T == f64)
                    return if (val) @as(f64, 1) else @as(f64, 0);

                return error.UnsupportedConversion;
            },

            // unconvertible types:
            .enumeration,
            .resource,
            .object,
            .event,
            .name,
            .objectlist,
            .sizelist,
            => return error.UnsupportedConversion,
        }
    }

    pub fn get(self: Value, comptime T: type) !T {
        if (@typeInfo(T) == .Enum and std.meta.Tag(T) == u8) {
            if (self != .enumeration) {
                logger.debug("invalid value: {} is not a enum (when querying {s})", .{
                    std.meta.activeTag(self),
                    @typeName(T),
                });
                return error.InvalidValue;
            }
            return std.meta.intToEnum(T, self.enumeration) catch |err| {
                logger.debug("invalid enum tag: {} is not contained in enum {s}", .{
                    self.enumeration,
                    @typeName(T),
                });
                return err;
            };
        }

        switch (T) {
            i32 => {
                if (self != .integer) return error.InvalidValue;
                return self.integer;
            },
            f32 => {
                if (self != .number) return error.InvalidValue;
                return self.number;
            },
            String => {
                if (self != .string) return error.InvalidValue;
                return self.string;
            },
            protocol.Margins => {
                if (self != .margins) return error.InvalidValue;
                return self.margins;
            },
            protocol.Color => {
                if (self != .color) return error.InvalidValue;
                return self.color;
            },
            protocol.Size => {
                if (self != .size) return error.InvalidValue;
                return self.size;
            },
            protocol.Point => {
                if (self != .point) return error.InvalidValue;
                return self.point;
            },
            protocol.ResourceID => {
                if (self != .resource) return error.InvalidValue;
                return self.resource;
            },
            bool => {
                if (self != .boolean) return error.InvalidValue;
                return self.boolean;
            },
            protocol.ObjectID => {
                if (self != .object) return error.InvalidValue;
                return self.object;
            },
            ObjectList => {
                if (self != .objectlist) return error.InvalidValue;
                return self.objectlist;
            },
            SizeList => {
                if (self != .sizelist) return error.InvalidValue;
                return self.sizelist;
            },
            protocol.EventID => {
                if (self != .event) return error.InvalidValue;
                return self.event;
            },
            protocol.WidgetName => {
                if (self != .name) return error.InvalidValue;
                return self.name;
            },
            else => @compileError(@typeName(T) ++ " is not a dunstblick primitive type"),
        }
    }

    pub fn serialize(self: Value, serializer: anytype, encode_type: bool) !void {
        @panic("not implemented yet!");
    }

    pub fn deserialize(allocator: *std.mem.Allocator, value_type: protocol.Type, decoder: *protocol.Decoder) !Value {
        return switch (value_type) {
            .enumeration => Value{
                .enumeration = try decoder.readByte(),
            },

            .integer => Value{
                .integer = try decoder.readVarSInt(),
            },

            .resource => Value{
                .resource = @intToEnum(protocol.ResourceID, try decoder.readVarUInt()),
            },

            .object => Value{
                .object = @intToEnum(protocol.ObjectID, try decoder.readVarUInt()),
            },

            .number => Value{
                .number = try decoder.readNumber(),
            },

            .boolean => Value{
                .boolean = ((try decoder.readByte()) != 0),
            },

            .color => Value{
                .color = .{
                    .red = try decoder.readByte(),
                    .green = try decoder.readByte(),
                    .blue = try decoder.readByte(),
                    .alpha = try decoder.readByte(),
                },
            },

            .size => Value{
                .size = .{
                    .width = try std.math.cast(u15, try decoder.readVarUInt()),
                    .height = try std.math.cast(u15, try decoder.readVarUInt()),
                },
            },

            .sizelist => blk: {
                const len = try decoder.readVarUInt();

                var list = SizeList.init(allocator);
                errdefer list.deinit();

                try list.resize(len);

                {
                    var i: usize = 0;
                    while (i < list.items.len) : (i += 4) {
                        var value: u8 = try decoder.readByte();

                        var j: usize = 0;
                        while (j < std.math.min(4, list.items.len - i)) : (j += 1) {
                            const size_type = @intToEnum(protocol.ColumnSizeType, @truncate(u2, (value >> @intCast(u3, 2 * j))));
                            list.items[i + j] = switch (size_type) {
                                .auto => protocol.ColumnSizeDefinition{ .auto = {} },
                                .expand => protocol.ColumnSizeDefinition{ .expand = {} },
                                .absolute => protocol.ColumnSizeDefinition{ .absolute = undefined },
                                .percentage => protocol.ColumnSizeDefinition{ .percentage = undefined },
                            };
                        }
                    }
                }

                for (list.items) |*item| {
                    switch (item.*) {
                        .absolute => |*v| v.* = try std.math.cast(u15, try decoder.readVarUInt()),
                        .percentage => |*v| v.* = @intToFloat(f32, std.math.clamp(try decoder.readByte(), 0, 100)) / 100.0,
                        else => {},
                    }
                }

                break :blk Value{ .sizelist = list };
            },

            .point => Value{
                .point = .{
                    .x = try std.math.cast(i15, try decoder.readVarSInt()),
                    .y = try std.math.cast(i15, try decoder.readVarSInt()),
                },
            },

            .string => blk: {
                const strlen = try decoder.readVarUInt();

                var string = std.ArrayList(u8).init(allocator);
                errdefer string.deinit();

                try string.resize(strlen);
                std.mem.copy(u8, string.items, try decoder.readRaw(strlen));

                break :blk Value{
                    .string = string,
                };
            },

            .margins => Value{
                .margins = .{
                    .left = try decoder.readVarUInt(),
                    .top = try decoder.readVarUInt(),
                    .right = try decoder.readVarUInt(),
                    .bottom = try decoder.readVarUInt(),
                },
            },

            .objectlist => blk: {
                const strlen = try decoder.readVarUInt();

                var list = std.ArrayList(protocol.ObjectID).init(allocator);
                errdefer list.deinit();

                try list.resize(strlen);

                for (list.items) |*id| {
                    id.* = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
                }

                break :blk Value{
                    .objectlist = list,
                };
            },

            .event => Value{
                .event = @intToEnum(protocol.EventID, try decoder.readVarUInt()),
            },

            .name => Value{
                .name = @intToEnum(protocol.WidgetName, try decoder.readVarUInt()),
            },
        };
    }
};

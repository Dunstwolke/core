const std = @import("std");
const protocol = @import("protocol.zig");

const logger = std.log.scoped(.dunstblick_value);

const types = @import("data-types.zig");

const Decoder = @import("decoder.zig").Decoder;

const String = types.String;
const ObjectList = types.ObjectList;
const SizeList = types.SizeList;

pub const Value = union(protocol.Type) {
    integer: i32,
    number: f32,
    string: String,
    enumeration: u8,
    margins: types.Margins,
    color: types.Color,
    size: types.Size,
    point: types.Point,
    resource: types.ResourceID,
    boolean: bool,
    object: types.ObjectID,
    objectlist: ObjectList,
    sizelist: SizeList,
    event: types.EventID,
    widget: types.WidgetName,

    pub fn deinit(self: *Value) void {
        switch (self.*) {
            .string => |*list| list.deinit(),
            .objectlist => |*list| list.deinit(),
            .sizelist => |*list| list.deinit(),
            else => {},
        }
        self.* = undefined;
    }

    fn convertIdentity(comptime value_type: protocol.Type, src: anytype) !Value {
        return switch (value_type) {
            value_type => @unionInit(Value, @tagName(value_type), src),
            else => return error.UnsupportedConversion,
        };
    }

    pub fn tryCreate(value_type: protocol.Type, src: anytype) !Value {
        const T = @TypeOf(src);
        if (comptime protocol.enums.isEnumeration(T)) {
            return switch (value_type) {
                .enumeration => Value{ .enumeration = @enumToInt(src) },
                else => return error.UnsupportedConversion,
            };
        }

        if (@typeInfo(T) == .Int) {
            return switch (value_type) {
                .boolean => Value{ .boolean = (src != 0) },
                .integer => Value{ .integer = src },
                .number => Value{ .number = @intToFloat(f32, src) },
                else => return error.UnsupportedConversion,
            };
        }

        return switch (T) {
            bool => switch (value_type) {
                .boolean => Value{ .boolean = src },
                .integer => Value{ .integer = @boolToInt(src) },
                .number => Value{ .number = @intToFloat(f32, @boolToInt(src)) },
                else => return error.UnsupportedConversion,
            },

            f16, f32, f64 => switch (value_type) {
                .integer => Value{ .integer = @floatToInt(i32, src) },
                .number => Value{ .number = @floatCast(f32, src) },
                else => return error.UnsupportedConversion,
            },

            // IDs
            protocol.ObjectID => try convertIdentity(.object, src),
            protocol.ResourceID => try convertIdentity(.resource, src),
            protocol.WidgetName => try convertIdentity(.name, src),
            protocol.EventID => try convertIdentity(.event, src),

            // Structures
            protocol.Size => try convertIdentity(.size, src),
            protocol.Point => try convertIdentity(.point, src),
            protocol.Color => try convertIdentity(.color, src),
            protocol.Margins => try convertIdentity(.margins, src),

            // complex types

            protocol.String => switch (value_type) {
                .integer => Value{ .integer = try std.fmt.parseInt(i32, src.get(), 0) },
                .number => Value{ .number = try std.fmt.parseFloat(f32, src.get()) },
                .string => Value{ .string = try src.clone() },
                else => return error.UnsupportedConversion,
            },

            protocol.ObjectList => switch (value_type) {
                .objectlist => blk: {
                    var list = ObjectList.init(src.allocator);
                    try list.appendSlice(src.items);
                    break :blk Value{ .objectlist = list };
                },
                else => return error.UnsupportedConversion,
            },

            protocol.SizeList => switch (value_type) {
                .sizelist => blk: {
                    var list = SizeList.init(src.allocator);
                    try list.appendSlice(src.items);
                    break :blk Value{ .sizelist = list };
                },
                else => return error.UnsupportedConversion,
            },

            else => @compileError("No possible conversion from " ++ @typeName(T)),
        };
    }

    pub const ConvertError = error{ OutOfMemory, UnsupportedConversion };
    pub fn convertTo(self: Value, comptime T: type, opt_allocator: ?*std.mem.Allocator) ConvertError!T {
        if (self.get(T)) |v| {
            return v;
        } else |_| {
            // we ignore the conversion error, we just want to short-cut
            // the conversion path when a compatible type is queried.
        }

        const ti = @typeInfo(T);

        switch (self) {
            .integer => |val| {
                if (opt_allocator) |allocator| {
                    if (T == String) {
                        var buf: [64]u8 = undefined;
                        const str = std.fmt.bufPrint(&buf, "{d:.3}", .{val}) catch unreachable;
                        return try String.init(allocator, str);
                    }
                }
                return error.UnsupportedConversion;
            },
            .number => |val| {
                if (opt_allocator) |allocator| {
                    if (T == String) {
                        var buf: [64]u8 = undefined;
                        const str = std.fmt.bufPrint(&buf, "{d:.3}", .{val}) catch unreachable;
                        return try String.init(allocator, str);
                    }
                }
                return error.UnsupportedConversion;
            },
            .string => return error.UnsupportedConversion,
            .margins => return error.UnsupportedConversion,
            .color => return error.UnsupportedConversion,
            .size => return error.UnsupportedConversion,
            .point => return error.UnsupportedConversion,

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
            .widget,
            .objectlist,
            .sizelist,
            => return error.UnsupportedConversion,
        }
    }

    pub fn get(self: Value, comptime T: type) !T {
        if (comptime protocol.enums.isEnumeration(T)) {
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
            types.Margins => {
                if (self != .margins) return error.InvalidValue;
                return self.margins;
            },
            types.Color => {
                if (self != .color) return error.InvalidValue;
                return self.color;
            },
            types.Size => {
                if (self != .size) return error.InvalidValue;
                return self.size;
            },
            types.Point => {
                if (self != .point) return error.InvalidValue;
                return self.point;
            },
            types.ResourceID => {
                if (self != .resource) return error.InvalidValue;
                return self.resource;
            },
            bool => {
                if (self != .boolean) return error.InvalidValue;
                return self.boolean;
            },
            types.ObjectID => {
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
            types.EventID => {
                if (self != .event) return error.InvalidValue;
                return self.event;
            },
            types.WidgetName => {
                if (self != .widget) return error.InvalidValue;
                return self.widget;
            },
            else => @compileError(@typeName(T) ++ " is not a dunstblick primitive type"),
        }
    }

    pub fn serialize(self: Value, serializer: anytype, encode_type: bool) !void {
        if (encode_type) {
            try serializer.writeByte(@enumToInt(std.meta.activeTag(self)));
        }

        return switch (self) {
            .enumeration => |val| try serializer.writeByte(val),

            .number => |val| try serializer.writeNumber(val),

            .boolean => |val| try serializer.writeByte(@boolToInt(val)),

            .integer => |val| try serializer.writeVarSInt(val),

            .resource => |val| try serializer.writeVarUInt(@enumToInt(val)),

            .object => |val| try serializer.writeVarUInt(@enumToInt(val)),

            .event => |val| try serializer.writeVarUInt(@enumToInt(val)),

            .widget => |val| try serializer.writeVarUInt(@enumToInt(val)),

            .color => |val| {
                try serializer.writeByte(val.red);
                try serializer.writeByte(val.green);
                try serializer.writeByte(val.blue);
                try serializer.writeByte(val.alpha);
            },

            .size => |val| {
                try serializer.writeVarUInt(val.width);
                try serializer.writeVarUInt(val.height);
            },

            .point => |val| {
                try serializer.writeVarSInt(val.x);
                try serializer.writeVarSInt(val.y);
            },

            .margins => |val| {
                try serializer.writeVarUInt(val.left);
                try serializer.writeVarUInt(val.top);
                try serializer.writeVarUInt(val.right);
                try serializer.writeVarUInt(val.bottom);
            },

            .string => |val| {
                const slice = val.get();

                try serializer.writeVarUInt(@intCast(u32, slice.len));
                try serializer.writeRaw(slice);
            },

            .objectlist => |val| {
                const slice = val.items;
                try serializer.writeVarUInt(@intCast(u32, slice.len));
                for (slice) |id| {
                    try serializer.writeVarUInt(@enumToInt(id));
                }
            },

            .sizelist => |val| {
                const slice = val.items;

                try serializer.writeVarUInt(@intCast(u32, slice.len));

                {
                    var i: usize = 0;
                    while (i < slice.len) : (i += 4) {
                        var value: u8 = 0;

                        var j: usize = 0;
                        while (j < std.math.min(4, slice.len - i)) : (j += 1) {
                            const bits = @enumToInt(slice[i + j]);
                            value |= (@as(u8, bits) << @intCast(u3, 2 * j));
                        }

                        try serializer.writeByte(value);
                    }
                }

                for (slice) |item| {
                    switch (item) {
                        .absolute => |v| try serializer.writeVarUInt(v),
                        .percentage => |v| {
                            std.debug.assert(v >= 0.0 and v <= 1.0);
                            try serializer.writeByte(@floatToInt(u8, 100.0 * v));
                        },
                        else => {},
                    }
                }
            },
        };
    }

    pub fn deserialize(allocator: *std.mem.Allocator, value_type: types.Type, decoder: *Decoder) !Value {
        return switch (value_type) {
            .enumeration => Value{
                .enumeration = try decoder.readByte(),
            },

            .integer => Value{
                .integer = try decoder.readVarSInt(),
            },

            .resource => Value{
                .resource = @intToEnum(types.ResourceID, try decoder.readVarUInt()),
            },

            .object => Value{
                .object = @intToEnum(types.ObjectID, try decoder.readVarUInt()),
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
                            const size_type = @intToEnum(types.ColumnSizeType, @truncate(u2, (value >> @intCast(u3, 2 * j))));
                            list.items[i + j] = switch (size_type) {
                                .auto => types.ColumnSizeDefinition{ .auto = {} },
                                .expand => types.ColumnSizeDefinition{ .expand = {} },
                                .absolute => types.ColumnSizeDefinition{ .absolute = undefined },
                                .percentage => types.ColumnSizeDefinition{ .percentage = undefined },
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
                    .string = .{ .dynamic = string },
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

                var list = std.ArrayList(types.ObjectID).init(allocator);
                errdefer list.deinit();

                try list.resize(strlen);

                for (list.items) |*id| {
                    id.* = @intToEnum(types.ObjectID, try decoder.readVarUInt());
                }

                break :blk Value{
                    .objectlist = list,
                };
            },

            .event => Value{
                .event = @intToEnum(types.EventID, try decoder.readVarUInt()),
            },

            .widget => Value{
                .widget = @intToEnum(types.WidgetName, try decoder.readVarUInt()),
            },
        };
    }
};

const std = @import("std");
const zero_graphics = @import("zero-graphics");

const protocol = @import("dunstblick-protocol");
const logger = std.log.scoped(.dunstblick_ui);

const DunstblickUI = @This();

allocator: *std.mem.Allocator,

objects: std.AutoArrayHashMapUnmanaged(protocol.ObjectID, Object),
resources: std.AutoArrayHashMapUnmanaged(protocol.ResourceID, Resource),

pub fn init(allocator: *std.mem.Allocator) DunstblickUI {
    return DunstblickUI{
        .allocator = allocator,
        .objects = .{},
        .resources = .{},
    };
}

pub fn deinit(self: *DunstblickUI) void {
    {
        var it = self.resources.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.data.deinit(self.allocator);
        }
    }
    self.resources.deinit(self.allocator);

    {
        var it = self.objects.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
    }
    self.objects.deinit(self.allocator);

    self.* = undefined;
}

pub fn addOrReplaceResource(self: *DunstblickUI, id: protocol.ResourceID, kind: protocol.ResourceKind, data: []const u8) !void {
    const gop = try self.resources.getOrPut(self.allocator, id);
    if (!gop.found_existing) {
        gop.value_ptr.* = .{
            .kind = kind,
            .data = .{},
        };
    }

    gop.value_ptr.kind = kind;

    try gop.value_ptr.data.resize(self.allocator, data.len);
    std.mem.copy(u8, gop.value_ptr.data.items, data);
}

pub fn addOrUpdateObject(self: *DunstblickUI, id: protocol.ObjectID, obj: Object) !void {
    const gop = try self.objects.getOrPut(self.allocator, id);
    if (gop.found_existing) {
        gop.value_ptr.deinit();
    }
    gop.value_ptr.* = obj;
}

pub fn removeObject(self: *DunstblickUI, oid: protocol.ObjectID) void {
    if (self.objects.fetchSwapRemove(oid)) |kv| {
        var copy = kv.value;
        copy.deinit();
    }
}

pub fn setView(self: *DunstblickUI, resource: protocol.ResourceID) !void {
    logger.err("setView({}) not implemented yet!", .{@enumToInt(resource)});
}

pub fn setRoot(self: *DunstblickUI, object: protocol.ObjectID) !void {
    logger.err("setRoot({}) not implemented yet!", .{@enumToInt(object)});
}

pub fn getObject(self: *DunstblickUI, id: protocol.ObjectID) ?*Object {
    return if (self.objects.getEntry(id)) |entry|
        entry.value_ptr
    else
        null;
}

pub const Resource = struct {
    kind: protocol.ResourceKind,
    data: std.ArrayListUnmanaged(u8),
};

pub const Object = struct {
    allocator: *std.mem.Allocator,
    properties: std.AutoArrayHashMapUnmanaged(protocol.PropertyName, Value),

    pub fn init(allocator: *std.mem.Allocator) Object {
        return Object{
            .allocator = allocator,
            .properties = .{},
        };
    }

    pub fn deinit(self: *Object) void {
        {
            var it = self.properties.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
        }
        self.properties.deinit(self.allocator);
        self.* = undefined;
    }

    /// Adds a property. If the property already exists, returns `error.AlreadyExists`.
    pub fn addProperty(self: *Object, name: protocol.PropertyName, value: Value) !void {
        const gop = try self.properties.getOrPut(self.allocator, name);
        if (gop.found_existing)
            return error.AlreadyExists;
        gop.value_ptr.* = value;
    }

    /// Adds a property. If the property already exists, overrides the previous value.
    pub fn setProperty(self: *Object, name: protocol.PropertyName, value: Value) !void {
        const gop = try self.properties.getOrPut(self.allocator, name);
        if (gop.found_existing) {
            gop.value_ptr.deinit();
        }
        gop.value_ptr.* = value;
    }

    fn getList(self: *Object, prop_name: protocol.PropertyName) !*ObjectList {
        if (self.properties.getEntry(prop_name)) |entry| {
            if (entry.value_ptr.* == .objectlist) {
                return &entry.value_ptr.objectlist;
            } else {
                return error.TypeMismatch;
            }
        } else {
            return error.PropertyNotFound;
        }
    }

    pub fn clear(self: *Object, prop_name: protocol.PropertyName) !void {
        const list = try self.getList(prop_name);
        @panic("not implemented yet!");
    }

    pub fn insertRange(self: *Object, prop_name: protocol.PropertyName, index: usize, items: []const protocol.ObjectID) !void {
        const list = try self.getList(prop_name);
        @panic("not implemented yet!");
    }

    pub fn removeRange(self: *Object, prop_name: protocol.PropertyName, index: usize, count: usize) !void {
        const list = try self.getList(prop_name);
        @panic("not implemented yet!");
    }

    pub fn moveRange(self: *Object, prop_name: protocol.PropertyName, index_from: usize, index_to: usize, count: usize) !void {
        const list = try self.getList(prop_name);
        @panic("not implemented yet!");
    }
};

const ObjectList = std.ArrayList(protocol.ObjectID);
const String = std.ArrayList(u8);

pub const Value = union(protocol.Type) {
    none,
    integer: i32,
    number: f32,
    string: String,
    enumeration: u8,
    margins: protocol.Margins,
    color: zero_graphics.Color,
    size: zero_graphics.Size,
    point: zero_graphics.Point,
    resource: protocol.ResourceID,
    boolean: bool,
    object: protocol.ObjectID,
    objectlist: ObjectList,
    event: protocol.EventID,
    name: protocol.WidgetName,

    pub fn deserialize(allocator: *std.mem.Allocator, value_type: protocol.Type, decoder: *protocol.Decoder) !Value {
        return switch (value_type) {
            .none => .none, // usage fault

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
                    .r = try decoder.readByte(),
                    .g = try decoder.readByte(),
                    .b = try decoder.readByte(),
                    .a = try decoder.readByte(),
                },
            },

            .size => Value{
                .size = .{
                    .width = try std.math.cast(u15, try decoder.readVarUInt()),
                    .height = try std.math.cast(u15, try decoder.readVarUInt()),
                },
            },

            .point => Value{
                .point = .{
                    .x = try std.math.cast(i15, try decoder.readVarSInt()),
                    .y = try std.math.cast(i15, try decoder.readVarSInt()),
                },
            },

            // HOW?
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

            _ => return error.NotSupported,
        };
    }

    pub fn deinit(self: *Value) void {
        switch (self.*) {
            .string => |*list| list.deinit(),
            .objectlist => |*list| list.deinit(),
            else => {},
        }
        self.* = undefined;
    }
};

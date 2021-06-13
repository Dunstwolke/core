const std = @import("std");
const zero_graphics = @import("zero-graphics");

const protocol = @import("dunstblick-protocol");
const logger = std.log.scoped(.dunstblick_ui);

const DunstblickUI = @This();

allocator: *std.mem.Allocator,

objects: std.AutoArrayHashMapUnmanaged(protocol.ObjectID, Object),
resources: std.AutoArrayHashMapUnmanaged(protocol.ResourceID, Resource),

current_view: ?WidgetTree,
root_object: ?protocol.ObjectID,

pub fn init(allocator: *std.mem.Allocator) DunstblickUI {
    return DunstblickUI{
        .allocator = allocator,
        .objects = .{},
        .resources = .{},
        .current_view = null,
        .root_object = null,
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

pub fn processUserInterface(self: *DunstblickUI, rectangle: zero_graphics.Rectangle, ui: zero_graphics.UserInterface.Builder) !void {
    if (self.current_view) |*view| {
        const root_object = if (self.root_object) |obj_id|
            self.objects.getPtr(obj_id)
        else
            null;

        try view.updateBindings(root_object);
        view.updateWantedSize(ui.ui);
        view.layout(rectangle);

        try view.processUserInterface(ui);
    }
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

pub fn setView(self: *DunstblickUI, id: protocol.ResourceID) !void {
    const resource = self.resources.get(id) orelse return error.ResourceNotFound;

    var decoder = protocol.Decoder.init(resource.data.items);

    var tree = try WidgetTree.deserialize(self, self.allocator, &decoder);
    errdefer tree.deinit();

    if (self.current_view) |*view| {
        view.deinit();
    }

    self.current_view = tree;
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

    pub fn getProperty(self: *Object, name: protocol.PropertyName) ?*Value {
        if (self.properties.getEntry(name)) |entry| {
            return entry.value_ptr;
        } else {
            return null;
        }
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
const SizeList = std.ArrayList(protocol.ColumnSizeDefinition);
const String = std.ArrayList(u8);

pub const Value = union(protocol.Type) {
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

fn isProperty(comptime T: type) bool {
    return @typeInfo(T) == .Struct and @hasDecl(T, "property_tag");
}

pub fn Property(comptime T: type) type {
    comptime {
        if (@typeInfo(T) != .Enum) {
            for (std.meta.fields(Value)) |field| {
                if (field.field_type == T)
                    break;
            } else @compileError(@typeName(T) ++ " is not a supported property type");
        }
    }
    return struct {
        const Self = @This();

        /// this marks the type as a bindable property
        pub const property_tag = {};

        /// The type of the property
        pub const Type = T;

        value: T,
        binding: ?protocol.PropertyName = null,

        pub fn get(self: Self, binding_context: ?*Object) T {
            if (self.binding != null and binding_context != null) {
                if (binding_context.?.getProperty(self.binding.?)) |value| {
                    if (value.convertTo(T)) |val| {
                        return val;
                    } else |err| {
                        logger.warn("binding error: converting {}) of type {s} to {s} failed: {}", .{
                            self.binding.?,
                            @tagName(std.meta.activeTag(value.*)),
                            @typeName(T),
                            err,
                        });
                    }
                }
            }
            return self.value;
        }

        pub fn set(self: *Self, binding_context: ?Object, value: T) !void {
            std.debug.assert(binding_context == null); // TODO: Implement the pass-through
            switch (T) {
                ObjectList => {
                    try self.value.resize(value.items.len);
                    std.mem.copy(protocol.ObjectID, self.value.items, value.items);
                    var copy = value;
                    copy.deinit();
                },

                SizeList => {
                    try self.value.resize(value.items.len);
                    std.mem.copy(protocol.ColumnSizeDefinition, self.value.items, value.items);
                    var copy = value;
                    copy.deinit();
                },

                String => {
                    try self.value.resize(value.items.len);
                    std.mem.copy(u8, self.value.items, value.items);
                    var copy = value;
                    copy.deinit();
                },

                // trivial cases can be made with this
                else => self.value = value,
            }
        }

        pub fn deinit(self: *Self) void {
            switch (T) {
                ObjectList, SizeList, String => self.value.deinit(),

                // trivial cases can be made with this
                else => {},
            }
            self.* = undefined;
        }
    };
}

fn deinitAllProperties(comptime T: type, container: *T) void {
    inline for (std.meta.fields(T)) |fld| {
        if (comptime isProperty(fld.field_type)) {
            const property = &@field(container, fld.name);
            property.deinit();
        }
    }
}

pub const WidgetTree = struct {
    allocator: *std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    root: Widget,
    ui: *DunstblickUI,

    pub fn deserialize(ui: *DunstblickUI, allocator: *std.mem.Allocator, decoder: *protocol.Decoder) !WidgetTree {
        var tree = WidgetTree{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .root = undefined,
            .ui = ui,
        };
        errdefer tree.arena.deinit();

        // We allocate the static part of the widget tree into the arena, makes it easier
        // to free the data later
        try tree.deserializeWidget(&tree.root, decoder);

        return tree;
    }

    const DeserializeWidgetError = error{
        OutOfMemory,
        EndOfStream,
        InvalidEnumTag,
        Overflow,
        InvalidValue,
    };

    const ValueFromStream = union(enum) {
        value: Value,
        binding: protocol.PropertyName,
    };

    fn setValue(property: anytype, property_id: protocol.Property, value_from_stream: ValueFromStream) !bool {
        switch (value_from_stream) {
            .value => |untyped_value| {
                const typed_value = try untyped_value.get(@TypeOf(property.*).Type);
                try property.set(null, typed_value);
            },
            .binding => |id| {
                property.binding = id;
            },
        }
        return true;
    }

    fn setPropertyValue(comptime T: type, container: *T, property_id: protocol.Property, value_from_stream: ValueFromStream) !bool {
        inline for (std.meta.fields(T)) |fld| {
            if (comptime isProperty(fld.field_type)) {
                if (property_id == @field(protocol.Property, fld.name)) {
                    const property = &@field(container, fld.name);
                    return setValue(property, property_id, value_from_stream);
                }
            }
        }
        return false;
    }

    fn setActiveControlPropertyValue(widget: *Widget, property_id: protocol.Property, value_from_stream: ValueFromStream) !bool {
        inline for (std.meta.fields(Control)) |control_fld| {
            if (widget.control == @field(protocol.WidgetType, control_fld.name)) {
                return setPropertyValue(control_fld.field_type, &@field(widget.control, control_fld.name), property_id, value_from_stream);
            }
        }
        unreachable;
    }

    fn deserializeWidget(self: *WidgetTree, widget: *Widget, decoder: *protocol.Decoder) DeserializeWidgetError!void {
        const root_type = try decoder.readEnum(protocol.WidgetType);

        try self.deserializeChildWidget(widget, decoder, root_type);
    }

    fn deserializeChildWidget(self: *WidgetTree, widget: *Widget, decoder: *protocol.Decoder, widget_type: protocol.WidgetType) DeserializeWidgetError!void {
        widget.* = Widget.init(self.allocator, widget_type);
        errdefer widget.deinit();

        // logger.debug("deserialize widget of type {}", .{widget_type});

        // read properites
        while (true) {
            const property_tag = try decoder.readByte();
            if (property_tag == 0)
                break;

            var property_id = try std.meta.intToEnum(protocol.Property, property_tag & 0x7F);

            var from_stream = if ((property_tag & 0x80) != 0) blk: {
                const property_name = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());

                // logger.debug("property {} is bound to {}", .{ property_id, property_name });

                break :blk ValueFromStream{ .binding = property_name };
            } else blk: {
                const property_type = for (protocol.layout_format.properties) |desc| {
                    if (desc.value == property_id)
                        break desc.type;
                } else unreachable;

                // logger.debug("read {} of type {}", .{ property_id, property_type });

                var value = try Value.deserialize(self.allocator, property_type, decoder);
                break :blk ValueFromStream{ .value = value };
            };

            // find the proper property

            errdefer switch (from_stream) {
                .value => |*value| value.deinit(),
                .binding => {},
            };

            var found_property = try setPropertyValue(Widget, widget, property_id, from_stream);
            if (!found_property) {
                found_property = try setActiveControlPropertyValue(widget, property_id, from_stream);
            }
            if (!found_property) {
                logger.warn("property {} does not exist on widget {}", .{ property_id, widget_type });
                switch (from_stream) {
                    .value => |*value| value.deinit(),
                    .binding => {},
                }
                // TODO : Think about this:
                // Is it required that a layout format is properly compiled?
                // Related: format versions, future properties, …
                if (std.builtin.mode != .Debug) {
                    return error.InvalidProperty;
                }
            }
        }

        // read children
        while (true) {
            const widget_type_tag = try decoder.readByte();
            if (widget_type_tag == 0)
                break;
            const child_type = try std.meta.intToEnum(protocol.WidgetType, widget_type_tag);

            const child = try widget.children.addOne();
            errdefer _ = widget.children.pop();

            try self.deserializeChildWidget(child, decoder, child_type);
        }
    }

    pub fn deinit(self: *WidgetTree) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn updateBindings(self: *WidgetTree, root_object: ?*Object) !void {
        return self.updateBindingsForWidget(&self.root, root_object);
    }

    const UpdateBindingsForWidgetError = error{
        ResourceMismatch,
        InvalidLayout,
        OutOfMemory,
    };

    fn updateBindingsForWidget(self: *WidgetTree, widget: *Widget, parent_binding_source: ?*Object) UpdateBindingsForWidgetError!void {
        // STAGE 1: Update the current binding source

        // if we have a bindingSource of the parent available:
        if (parent_binding_source != null and widget.binding_context.binding != null) {
            // check if the parent source has the property
            // we bind our bindingContext to and if yes,
            // bind to it

            if (parent_binding_source.?.getProperty(widget.binding_context.binding.?)) |binding_value| {
                if (binding_value.get(protocol.ObjectID)) |binding_id| {
                    widget.binding_source = self.ui.getObject(binding_id);
                } else |err| {
                    logger.warn("failed to convert {} to object id", .{
                        widget.binding_context.binding.?,
                    });
                    widget.binding_source = null;
                }
            } else {
                widget.binding_source = null;
            }
        } else {
            // otherwise check if our bindingContext has a valid resourceID and
            // load that resource reference:
            const object_id = widget.get(.binding_context);
            widget.binding_source = if (self.ui.getObject(object_id)) |obj|
                obj
            else
                parent_binding_source;
        }

        // STAGE 2: Update child widgets.

        const child_template_id = widget.get(.child_template);
        if (self.ui.resources.get(child_template_id)) |resource| {
            // if we have a child binding and the resource for it exists,
            // update the child list
            if (resource.kind != .layout)
                return error.ResourceMismatch; // TODO: find a nicer solution here

            var child_source = widget.get(.child_source);

            const current_len = widget.children.items.len;
            const new_len = child_source.items.len;

            if (current_len > new_len) {
                for (widget.children.items[new_len..]) |*child| {
                    child.deinit();
                }
            }
            try widget.children.resize(new_len);

            // just initialze all new widgets to spacers,
            // which have no special configuration requirements.
            // When everything will be cleaned up, the new elements
            // are all readily initialized.
            for (widget.children.items[current_len..]) |*items| {
                items.* = Widget.init(self.allocator, .spacer);
            }

            std.debug.assert(widget.children.items.len == child_source.items.len);

            for (widget.children.items) |*child, i| {
                if (child.template_id == null or child.template_id.? != child_template_id) {
                    var decoder = protocol.Decoder.init(resource.data.items);

                    var new_child: Widget = undefined;
                    self.deserializeWidget(&new_child, &decoder) catch |err| {
                        logger.err("failed to deserialize layout: {}", .{err});
                        return error.InvalidLayout;
                    };
                    new_child.template_id = child_template_id;

                    child.deinit();
                    child.* = new_child;
                }

                // update the children with the list as
                // parent item:
                // this rebinds the logic such that each child
                // will bind to the list item instead
                // of the actual binding context :)

                try self.updateBindingsForWidget(child, self.ui.getObject(child_source.items[i]));
            }
        } else {
            // if not, just update all children regulary
            for (widget.children.items) |*child| {
                try self.updateBindingsForWidget(child, widget.binding_source);
            }
        }
    }

    pub fn updateWantedSize(self: *WidgetTree, ui: *zero_graphics.UserInterface) void {
        self.updateWantedSizeForWidget(&self.root, ui);
    }

    fn updateWantedSizeForWidget(self: *WidgetTree, widget: *Widget, ui: *zero_graphics.UserInterface) void {
        for (widget.children.items) |*child| {
            self.updateWantedSizeForWidget(child, ui);
        }
        self.computeWantedSize(widget, ui);
    }

    fn computeWantedSize(self: *WidgetTree, widget: *Widget, ui: *zero_graphics.UserInterface) void {
        // WARNING: MUST CAPTURE BY POINTER AS WE USE @fieldParentPtr!
        widget.wanted_size = switch (widget.control) {

            // TODO: Implement size computation logic here :)
            .label => |*label| blk: {
                const str = label.get(.text);

                const rectangle = ui.renderer.measureString(ui.default_font, str.items);

                break :blk rectangle.size();
            },

            .separator => .{
                .width = 5,
                .height = 5,
            },

            .progressbar => .{
                .width = 256,
                .height = 32,
            },

            .checkbox, .radiobutton => .{
                .width = 32,
                .height = 32,
            },

            .slider => .{
                .width = 32,
                .height = 32,
            },

            .picture => blk: {
                // TODO: Implement picture logic
                logger.err("computeWantedSize(picture) not implemented yet!", .{});

                break :blk .{
                    .width = 256,
                    .height = 256,
                };
            },

            .scrollbar => |*scrollbar| blk: {
                const orientation = scrollbar.get(.orientation);

                break :blk switch (orientation) {
                    .horizontal => zero_graphics.Size{ .width = 64, .height = 24 },
                    .vertical => zero_graphics.Size{ .width = 24, .height = 64 },
                };
            },

            .scrollview => |*scrollview| blk: {
                logger.err("computeWantedSize(scrollview) not implemented yet!", .{});

                break :blk .{
                    .width = 256,
                    .height = 256,
                };
            },

            .stack_layout => |*stack_layout| blk: {
                const paddings = widget.get(.paddings);
                const orientation = stack_layout.get(.orientation);

                var size = zero_graphics.Size.empty;
                switch (orientation) {
                    .vertical => for (widget.children.items) |*child| {
                        if (child.getActualVisibility() == .collapsed)
                            continue;
                        const child_size = child.getWantedSizeWithMargins();
                        size.width = std.math.max(size.width, child_size.width);
                        size.height += child_size.height;
                    },
                    .horizontal => for (widget.children.items) |*child| {
                        if (child.getActualVisibility() == .collapsed)
                            continue;
                        const child_size = child.getWantedSizeWithMargins();
                        size.width += child_size.width;
                        size.height = std.math.max(size.height, child_size.height);
                    },
                }
                size.width += mapToU15(paddings.totalHorizontal());
                size.height += mapToU15(paddings.totalVertical());
                break :blk size;
            },

            // default logic
            else => blk: {
                var size = widget.get(.size_hint);
                for (widget.children.items) |child| {
                    const child_size = child.getWantedSizeWithMargins();
                    size.width = std.math.max(size.width, child_size.width);
                    size.height = std.math.max(size.height, child_size.height);
                }
                break :blk convertSizeToZeroG(size);
            },
        };
    }

    pub fn layout(self: *WidgetTree, rectangle: zero_graphics.Rectangle) void {
        self.layoutWidget(&self.root, rectangle);
    }

    fn clampSub(a: u15, b: u32) u15 {
        return if (b < a)
            a - @truncate(u15, b)
        else
            0;
    }

    fn layoutWidget(self: *WidgetTree, widget: *Widget, _bounds: zero_graphics.Rectangle) void {
        const margins = widget.get(.margins);
        const padding = widget.get(.paddings);
        const horizontal_alignment = widget.get(.horizontal_alignment);
        const vertical_alignment = widget.get(.vertical_alignment);

        const bounds = zero_graphics.Rectangle{
            .x = _bounds.x + @intCast(u15, margins.left),
            .y = _bounds.y + @intCast(u15, margins.top),
            .width = clampSub(_bounds.width, margins.totalHorizontal()), // safety check against underflow
            .height = clampSub(_bounds.height, margins.totalVertical()),
        };

        var target: zero_graphics.Rectangle = undefined;
        switch (horizontal_alignment) {
            .stretch => {
                target.width = bounds.width;
                target.x = 0;
            },
            .left => {
                target.width = std.math.min(widget.wanted_size.width, bounds.width);
                target.x = 0;
            },
            .center => {
                target.width = std.math.min(widget.wanted_size.width, bounds.width);
                target.x = (bounds.width - target.width) / 2;
            },
            .right => {
                target.width = std.math.min(widget.wanted_size.width, bounds.width);
                target.x = bounds.width - target.width;
            },
        }
        target.x += bounds.x;

        switch (vertical_alignment) {
            .stretch => {
                target.height = bounds.height;
                target.y = 0;
            },
            .top => {
                target.height = std.math.min(widget.wanted_size.height, bounds.height);
                target.y = 0;
            },
            .middle => {
                target.height = std.math.min(widget.wanted_size.height, bounds.height);
                target.y = (bounds.height - target.height) / 2;
            },
            .bottom => {
                target.height = std.math.min(widget.wanted_size.height, bounds.height);
                target.y = bounds.height - target.height;
            },
        }
        target.y += bounds.y;

        widget.actual_bounds = target;

        const child_area = zero_graphics.Rectangle{
            .x = widget.actual_bounds.x + @intCast(u15, padding.left),
            .y = widget.actual_bounds.y + @intCast(u15, padding.top),
            .width = clampSub(widget.actual_bounds.width, padding.totalHorizontal()),
            .height = clampSub(widget.actual_bounds.height, padding.totalVertical()),
        };

        self.layoutChildren(widget, child_area);
    }

    fn layoutChildren(self: *WidgetTree, widget: *Widget, rectangle: zero_graphics.Rectangle) void {
        // WARNING: MUST CAPTURE BY POINTER AS WE USE @fieldParentPtr!
        switch (widget.control) {

            // TODO: Implement layout logic here :)

            .stack_layout => |*stack_layout| {
                const stack_direction = stack_layout.get(.orientation);

                switch (stack_direction) {
                    .vertical => {
                        var rect = rectangle;
                        for (widget.children.items) |*child| {
                            if (child.getActualVisibility() == .collapsed)
                                continue;

                            rect.height = child.getWantedSizeWithMargins().height;
                            self.layoutWidget(child, rect);
                            rect.y += rect.height;
                        }
                    },

                    .horizontal => {
                        var rect = rectangle;
                        for (widget.children.items) |*child| {
                            if (child.getActualVisibility() == .collapsed)
                                continue;
                            rect.width = child.getWantedSizeWithMargins().width;
                            self.layoutWidget(child, rect);
                            rect.x += rect.width;
                        }
                    },
                }
            },

            .scrollview => |*view| {
                // TODO: This isn't the final logic
                for (widget.children.items) |*child| {
                    self.layoutWidget(child, rectangle);
                }
            },

            // default logic for "non-containers":
            else => {
                for (widget.children.items) |*child| {
                    self.layoutWidget(child, rectangle);
                }
            },
        }
    }

    pub fn processUserInterface(self: *WidgetTree, ui: zero_graphics.UserInterface.Builder) !void {
        try self.processUserInterfaceForWidget(&self.root, ui);
    }

    fn processUserInterfaceForWidget(self: *WidgetTree, widget: *Widget, ui: zero_graphics.UserInterface.Builder) zero_graphics.UserInterface.Builder.Error!void {
        try self.doWidgetLogic(widget, ui);

        for (widget.children.items) |*child| {
            try self.processUserInterfaceForWidget(child, ui);
        }
    }

    fn doWidgetLogic(self: *WidgetTree, widget: *Widget, ui: zero_graphics.UserInterface.Builder) !void {
        const rect = widget.actual_bounds;
        // WARNING: MUST CAPTURE BY POINTER AS WE USE @fieldParentPtr!
        switch (widget.control) {

            // TODO: Implement widget logic here :)

            .label => |*label| {
                const str = label.get(.text);
                try ui.label(rect, str.items, .{ .id = widget });
            },

            else => {
                var fmt: [128]u8 = undefined;

                try ui.panel(rect, .{ .id = widget });
                try ui.label(
                    rect,
                    std.fmt.bufPrint(&fmt, "{s} not implemented yet", .{@tagName(std.meta.activeTag(widget.control))}) catch unreachable,
                    .{
                        .id = widget,
                        .horizontal_alignment = .left,
                        .vertical_alignment = .top,
                    },
                );
            },
        }
    }
};

pub const Widget = struct {
    const Self = @This();

    usingnamespace PropertyGetSetMixin(Self, getBindingSource);

    /// The list of all children of this widget.
    children: std.ArrayList(Self),

    /// The control that is contained in this widget.
    control: Control,

    /// This is a (temporary) pointer to the object that provides the values
    /// of all bound properties.
    /// It is only valid *after* `updateBindings` was invoked and will be invalidated
    /// as soon as any change to the object hierarchy is done (insertion/deletion).
    binding_source: ?*Object,

    /// If this is not `null`, this widget was created from a certain template 
    /// and will be used to keep the widget alive after a resize of the parent 
    /// list.
    template_id: ?protocol.ResourceID,

    /// the space the widget says it needs to have.
    /// this is a hint to each layouting algorithm to auto-size the widget
    /// accordingly.
    /// This value is only valid after `updateWantedSize` is called.
    wanted_size: zero_graphics.Size,

    /// the position of the widget on the screen after layouting
    /// NOTE: this does not include the margins of the widget!
    /// This value is only valid after `layout` is called.
    actual_bounds: zero_graphics.Rectangle,

    // shared properties:

    horizontal_alignment: Property(protocol.enums.HorizontalAlignment),
    vertical_alignment: Property(protocol.enums.VerticalAlignment),

    margins: Property(protocol.Margins),
    paddings: Property(protocol.Margins),
    dock_site: Property(protocol.enums.DockSite),
    visibility: Property(protocol.enums.Visibility),
    enabled: Property(bool),
    hit_test_visible: Property(bool),
    binding_context: Property(protocol.ObjectID),
    child_source: Property(ObjectList),
    child_template: Property(protocol.ResourceID),

    widget_name: Property(protocol.WidgetName),
    tab_title: Property(String),
    size_hint: Property(protocol.Size),

    left: Property(i32),
    top: Property(i32),

    fn initControl(control_type: protocol.WidgetType, allocator: *std.mem.Allocator) Control {
        inline for (std.meta.fields(Control)) |field| {
            if (control_type == @field(protocol.WidgetType, field.name)) {
                return @unionInit(Control, field.name, field.field_type.init(allocator));
            }
        }
        unreachable;
    }

    pub fn init(allocator: *std.mem.Allocator, control_type: protocol.WidgetType) Widget {
        var control = initControl(control_type, allocator);

        return Widget{
            .children = std.ArrayList(Widget).init(allocator),
            .control = control,
            .binding_source = null,
            .template_id = null,
            .wanted_size = undefined,
            .actual_bounds = undefined,

            .horizontal_alignment = .{ .value = .stretch },
            .vertical_alignment = .{ .value = .stretch },
            .margins = .{ .value = protocol.Margins.all(0) },
            .paddings = .{ .value = protocol.Margins.all(0) },
            .dock_site = .{ .value = .left },
            .visibility = .{ .value = .visible },
            .enabled = .{ .value = true },
            .hit_test_visible = .{ .value = true },
            .binding_context = .{ .value = .invalid },
            .child_source = .{ .value = ObjectList.init(allocator) },
            .child_template = .{ .value = .invalid },
            .widget_name = .{ .value = .none },
            .tab_title = .{ .value = String.init(allocator) },
            .size_hint = .{ .value = protocol.Size{ .width = 0, .height = 0 } },
            .left = .{ .value = 0 },
            .top = .{ .value = 0 },
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit();

        self.control.deinit();

        deinitAllProperties(Self, self);

        self.* = undefined;
    }

    fn getBindingSource(self: *const Self) ?*Object {
        return self.binding_source;
    }

    pub fn getWantedSizeWithMargins(self: Self) zero_graphics.Size {
        return addMargin(self.wanted_size, self.get(.margins));
    }

    pub fn getActualVisibility(self: Self) protocol.enums.Visibility {
        // TODO: Implement rest!
        return self.get(.visibility);
    }
};

fn PropertyGetSetMixin(comptime Self: type, getBindingSource: fn (*const Self) ?*Object) type {
    return struct {
        fn PropertyType(comptime property_name: protocol.Property) type {
            const name = @tagName(property_name);
            if (@hasField(Self, name))
                return std.meta.fieldInfo(Self, @field(std.meta.FieldEnum(Self), name)).field_type.Type;

            @compileError("The property " ++ name ++ "does not exist on " ++ @typeName(Self));
        }

        /// Gets a property
        pub fn get(self: *const Self, comptime property_name: protocol.Property) PropertyType(property_name) {
            const name = @tagName(property_name);
            if (@hasField(Self, name)) {
                return @field(self, name).get(getBindingSource(self));
            } else {
                @compileError("The property " ++ name ++ "does not exist on " ++ @typeName(Self));
            }
        }

        /// Sets a property
        pub fn set(self: *Self, comptime property_name: protocol.Property, value: PropertyType(property_name)) auto {
            const name = @tagName(property_name);
            const name = @tagName(property_name);
            if (@hasField(Self, name)) {
                return @field(self, name).set(getBindingSource(self));
            } else {
                @compileError("The property " ++ name ++ "does not exist on " ++ @typeName(Self));
            }
        }
    };
}

fn GetBindingSource(comptime T: type, comptime t: protocol.WidgetType) fn (*const T) ?*Object {
    return struct {
        fn getBindingSource(self: *const T) ?*Object {
            // HACK: THIS IS A HORRIBLE HACK RIGHT NOW
            {
                var btn: Control.Button = undefined;
                var dummy = Control{ .button = btn };

                const delta = @ptrToInt(&dummy.button) - @ptrToInt(&dummy);
                std.debug.assert(delta == 0);
            }

            // we "know" from the code above that a pointer to union payload
            // is the same as the pointer to the union. This allows us converting
            // the control from inner to a Widget.

            const ctrl = @ptrCast(*const Control, @alignCast(@alignOf(Control), self));
            const parent = @fieldParentPtr(Widget, "control", ctrl);
            return parent.binding_source;
        }
    }.getBindingSource;
}

pub const Control = union(protocol.WidgetType) {
    button: Button,
    label: Label,
    combobox: EmptyControl,
    treeview: EmptyControl,
    listbox: EmptyControl,
    picture: Picture,
    textbox: EmptyControl,
    checkbox: CheckBox,
    radiobutton: RadioButton,
    scrollview: EmptyControl,
    scrollbar: ScrollBar,
    slider: Slider,
    progressbar: ProgressBar,
    spinedit: EmptyControl,
    separator: EmptyControl,
    spacer: EmptyControl,
    panel: EmptyControl,
    container: EmptyControl,
    tab_layout: TabLayout,
    canvas_layout: EmptyControl,
    flow_layout: EmptyControl,
    grid_layout: GridLayout,
    dock_layout: EmptyControl,
    stack_layout: StackLayout,

    pub fn deinit(self: *Control) void {
        inline for (std.meta.fields(Control)) |field| {
            if (self.* == @field(protocol.WidgetType, field.name)) {
                @field(self.*, field.name).deinit();
            }
        }
        self.* = undefined;
    }

    pub const EmptyControl = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .spacer));

        dummy: u32, // prevent zero-sizing

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .dummy = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Button = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .button));

        on_click: Property(protocol.EventID),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .on_click = .{ .value = .invalid },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Label = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .label));

        text: Property(String),
        font_family: Property(protocol.enums.Font),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .text = .{ .value = String.init(allocator) },
                .font_family = .{ .value = .sans },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Picture = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .picture));

        image: Property(protocol.ResourceID),
        image_scaling: Property(protocol.enums.ImageScaling),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .image = .{ .value = .invalid },
                .image_scaling = .{ .value = .stretch },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const CheckBox = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .checkbox));

        is_checked: Property(bool),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .is_checked = .{ .value = false },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const RadioButton = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .radiobutton));

        is_checked: Property(bool),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .is_checked = .{ .value = false },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const ScrollBar = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .scrollbar));

        minimum: Property(f32),
        maximum: Property(f32),
        value: Property(f32),
        orientation: Property(protocol.enums.Orientation),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .minimum = .{ .value = 0.0 },
                .maximum = .{ .value = 100.0 },
                .value = .{ .value = 25.0 },
                .orientation = .{ .value = .horizontal },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Slider = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .slider));

        minimum: Property(f32),
        maximum: Property(f32),
        value: Property(f32),
        orientation: Property(protocol.enums.Orientation),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .minimum = .{ .value = 0.0 },
                .maximum = .{ .value = 100.0 },
                .value = .{ .value = 0.0 },
                .orientation = .{ .value = .horizontal },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const ProgressBar = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .progressbar));

        minimum: Property(f32),
        maximum: Property(f32),
        value: Property(f32),
        orientation: Property(protocol.enums.Orientation),
        display_progress_style: Property(protocol.enums.DisplayProgressStyle),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .minimum = .{ .value = 0.0 },
                .maximum = .{ .value = 100.0 },
                .value = .{ .value = 0.0 },
                .orientation = .{ .value = .horizontal },
                .display_progress_style = .{ .value = .percent },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const StackLayout = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .stack_layout));

        orientation: Property(protocol.enums.StackDirection),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .orientation = .{ .value = .vertical },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const TabLayout = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .tab_layout));

        selected_index: Property(i32),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .selected_index = .{ .value = 0 },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const GridLayout = struct {
        const Self = @This();
        usingnamespace PropertyGetSetMixin(Self, GetBindingSource(Self, .grid_layout));

        rows: Property(SizeList),
        columns: Property(SizeList),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .rows = .{ .value = SizeList.init(allocator) },
                .columns = .{ .value = SizeList.init(allocator) },
            };
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };
};

fn mapToU15(value: u32) u15 {
    return std.math.cast(u15, value) catch std.math.maxInt(u15);
}

fn convertSizeToZeroG(size: protocol.Size) zero_graphics.Size {
    return zero_graphics.Size{
        .width = mapToU15(size.width),
        .height = mapToU15(size.height),
    };
}

fn addMargin(value: anytype, margin: protocol.Margins) @TypeOf(value) {
    const T = @TypeOf(value);
    return switch (T) {
        zero_graphics.Size, protocol.Size => T{
            .width = mapToU15(value.width + margin.totalHorizontal()),
            .height = mapToU15(value.height + margin.totalVertical()),
        },
        else => @compileError("Cannot add margins to " ++ @typeName(T)),
    };
}

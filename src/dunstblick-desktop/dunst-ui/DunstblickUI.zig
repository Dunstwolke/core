const std = @import("std");
const zero_graphics = @import("zero-graphics");

const protocol = @import("dunstblick-protocol");
const logger = std.log.scoped(.dunstblick_ui);

const DunstblickUI = @This();

allocator: *std.mem.Allocator,

objects: std.AutoArrayHashMapUnmanaged(protocol.ObjectID, Object),
resources: std.AutoArrayHashMapUnmanaged(protocol.ResourceID, Resource),

current_view: ?WidgetTree,

pub fn init(allocator: *std.mem.Allocator) DunstblickUI {
    return DunstblickUI{
        .allocator = allocator,
        .objects = .{},
        .resources = .{},
        .current_view = null,
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
        try view.processUserInterface(rectangle, ui);
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

    var tree = try WidgetTree.deserialize(self.allocator, &decoder);
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

    pub fn convertTo(self: Self, comptime T: type) !T {
        switch (self) {
            .integer => |val| return error.UnsupportedConversion,
            .number => |val| return error.UnsupportedConversion,
            .string => |val| return error.UnsupportedConversion,
            .enumeration => |val| return error.UnsupportedConversion,
            .margins => |val| return error.UnsupportedConversion,
            .color => |val| return error.UnsupportedConversion,
            .size => |val| return error.UnsupportedConversion,
            .point => |val| return error.UnsupportedConversion,
            .resource => |val| return error.UnsupportedConversion,
            .boolean => |val| return error.UnsupportedConversion,
            .object => |val| return error.UnsupportedConversion,
            .objectlist => |val| return error.UnsupportedConversion,
            .event => |val| return error.UnsupportedConversion,
            .name => |val| return error.UnsupportedConversion,
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

        pub fn get(self: Self, binding_context: ?Object) T {
            if (self.binding != null and binding_context != null) {
                if (binding_context.?.getProperty(self.binding.?)) |value| {
                    if (value.convertTo(T)) |val| {
                        return val;
                    } else |err| {
                        logger.warn("binding error: converting {}) of type {} to {} failed: {}", .{
                            self.binding.?,
                            @tagName(std.meta.activeTag(value.*)),
                            @typeName(T),
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
        if (@hasDecl(fld.field_type, "property_tag")) {
            const property = &@field(container, fld.name);
            property.deinit();
        }
    }
}

pub const WidgetTree = struct {
    allocator: *std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    root: Widget,

    pub fn deserialize(allocator: *std.mem.Allocator, decoder: *protocol.Decoder) !WidgetTree {
        var tree = WidgetTree{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .root = undefined,
        };
        errdefer tree.arena.deinit();

        const root_type = try decoder.readEnum(protocol.WidgetType);

        // We allocate the static part of the widget tree into the arena, makes it easier
        // to free the data later
        try tree.deserializeWidget(&tree.root, decoder, root_type);

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
            if (@hasDecl(fld.field_type, "property_tag")) {
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

    fn deserializeWidget(self: *WidgetTree, widget: *Widget, decoder: *protocol.Decoder, widget_type: protocol.WidgetType) DeserializeWidgetError!void {
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
                // TODO: Reinclude this when everything is properly implemented
                // return error.InvalidProperty;
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

            try self.deserializeWidget(child, decoder, child_type);
        }
    }

    pub fn deinit(self: *WidgetTree) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn processUserInterface(self: *WidgetTree, rectangle: zero_graphics.Rectangle, ui: zero_graphics.UserInterface.Builder) !void {
        // TODO: Implement proper rendering here

        const rect = zero_graphics.Rectangle{
            .x = rectangle.x + 10,
            .y = rectangle.y + 10,
            .width = rectangle.width - 20,
            .height = 24,
        };

        try ui.label(rect, "TODO: Implement WidgetTree", .{});
    }
};

pub const Widget = struct {
    const Self = @This();

    children: std.ArrayList(Self),
    control: Control,

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
};

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

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{};
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Button = struct {
        const Self = @This();

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

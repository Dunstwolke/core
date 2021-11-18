const std = @import("std");
const builtin = @import("builtin");
const zero_graphics = @import("zero-graphics");

const protocol = @import("dunstblick-protocol");
const logger = std.log.scoped(.dunstblick_ui);

pub usingnamespace @import("types.zig");

const types = @import("types.zig");

const DunstblickUI = @This();

const ResourceManager = zero_graphics.ResourceManager;

pub const FeedbackInterface = struct {
    pub const ErasedSelf = opaque {};
    pub const Error = error{ OutOfMemory, IoError };

    erased_self: *ErasedSelf,
    trigger_event: fn (self: *ErasedSelf, event: protocol.EventID, widget: protocol.WidgetName) Error!void,
    trigger_property_changed: fn (self: *ErasedSelf, oid: protocol.ObjectID, name: protocol.PropertyName, value: types.Value) Error!void,

    pub fn triggerEvent(self: @This(), event: protocol.EventID, widget: protocol.WidgetName) Error!void {
        return self.trigger_event(self.erased_self, event, widget);
    }

    pub fn triggerPropertyChanged(self: @This(), oid: protocol.ObjectID, name: protocol.PropertyName, value: types.Value) Error!void {
        return self.trigger_property_changed(self.erased_self, oid, name, value);
    }
};

allocator: *std.mem.Allocator,

objects: std.AutoArrayHashMapUnmanaged(protocol.ObjectID, types.Object),
resources: std.AutoArrayHashMapUnmanaged(protocol.ResourceID, Resource),

current_view: ?WidgetTree,
root_object: ?protocol.ObjectID,

interface: FeedbackInterface,

pub fn init(allocator: *std.mem.Allocator, interface: FeedbackInterface) DunstblickUI {
    return DunstblickUI{
        .allocator = allocator,
        .objects = .{},
        .resources = .{},

        .current_view = null,
        .root_object = null,

        .interface = interface,
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
        try view.updateWantedSize(ui.ui.renderer.?.resources, ui.ui);
        view.layout(rectangle);

        try view.processUserInterface(ui.ui.renderer.?.resources, ui);
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

pub fn addOrUpdateObject(self: *DunstblickUI, obj: types.Object) !void {
    const gop = try self.objects.getOrPut(self.allocator, obj.id);
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
    self.root_object = if (object != .invalid)
        object
    else
        null;
}

pub fn getObject(self: *DunstblickUI, id: protocol.ObjectID) ?*types.Object {
    return if (self.objects.getEntry(id)) |entry|
        entry.value_ptr
    else
        null;
}

fn triggerEvent(self: *DunstblickUI, event: protocol.EventID, widget: protocol.WidgetName) zero_graphics.UserInterface.Builder.Error!void {
    self.interface.triggerEvent(event, widget) catch |err| switch (err) {
        error.IoError => logger.err("{} while event {} was triggered for {}", .{ err, event, widget }),
        else => |e| return e,
    };
}

fn triggerPropertyChanged(self: *DunstblickUI, oid: protocol.ObjectID, name: protocol.PropertyName, value: types.Value) zero_graphics.UserInterface.Builder.Error!void {
    self.interface.triggerPropertyChanged(oid, name, value) catch |err| switch (err) {
        error.IoError => logger.err("{} while property {}.{} was changed to {}", .{ err, oid, name, value }),
        else => |e| return e,
    };
}

pub const Resource = struct {
    kind: protocol.ResourceKind,
    data: std.ArrayListUnmanaged(u8),

    cache_data: Cache = .none,

    const Cache = union(enum) {
        none,
        layout,
        bitmap: BitmapCache,
        drawing,
    };

    const BitmapCache = struct {
        resource_manager: *ResourceManager,
        texture: ?*ResourceManager.Texture,
    };

    fn getBitmap(self: *Resource, resource_manager: *zero_graphics.ResourceManager, ui: *zero_graphics.UserInterface) ?*ResourceManager.Texture {
        // TODO: Overhaul caching logic
        if (ui.renderer == null)
            @panic("usage error");
        if (self.kind != .bitmap)
            return null;
        if (self.cache_data == .none) {
            self.cache_data = .{ .bitmap = BitmapCache{
                .resource_manager = resource_manager,
                .texture = resource_manager.createTexture(.ui, ResourceManager.DecodePng{ .data = self.data.items }) catch |err| blk: {
                    logger.warn("Could not load resource as a bitmap: {s}", .{@errorName(err)});
                    break :blk null;
                },
            } };
        } else {
            std.debug.assert(self.cache_data == .bitmap);
        }
        return self.cache_data.bitmap.texture;
    }
};

fn isProperty(comptime T: type) bool {
    return @typeInfo(T) == .Struct and @hasDecl(T, "property_tag");
}

pub fn Property(comptime T: type) type {
    comptime {
        if (@typeInfo(T) != .Enum) {
            for (std.meta.fields(types.Value)) |field| {
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

        pub fn setUnderlying(self: *Self, value: T) void {
            std.debug.assert(self.binding == null);

            switch (T) {
                types.ObjectList, types.SizeList, types.String => self.value.deinit(),

                // trivial cases don't need deinit()
                else => {},
            }
            self.value = value;
        }

        pub fn deinit(self: *Self) void {
            switch (T) {
                types.ObjectList, types.SizeList, types.String => self.value.deinit(),

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

    const scroll_bar_size = 32;

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
        InvalidProperty,
    };

    const ValueFromStream = union(enum) {
        value: types.Value,
        binding: protocol.PropertyName,
    };

    fn setValue(property: anytype, value_from_stream: ValueFromStream) !bool {
        switch (value_from_stream) {
            .value => |untyped_value| {
                const typed_value = try untyped_value.get(@TypeOf(property.*).Type);

                // this is used in the widget deserializer, so we have no binding
                // by guarantee
                property.setUnderlying(typed_value);
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
                    return setValue(property, value_from_stream);
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
        widget.* = Widget.init(self.ui, self.allocator, widget_type);
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

                var value = try types.Value.deserialize(self.allocator, property_type, decoder);
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
                // if (builtin.mode != .Debug) {
                //     return error.InvalidProperty;
                // }
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

    pub fn updateBindings(self: *WidgetTree, root_object: ?*types.Object) !void {
        return self.updateBindingsForWidget(&self.root, root_object);
    }

    const UpdateBindingsForWidgetError = error{
        ResourceMismatch,
        InvalidLayout,
        OutOfMemory,
    };

    fn updateBindingsForWidget(self: *WidgetTree, widget: *Widget, parent_binding_source: ?*types.Object) UpdateBindingsForWidgetError!void {
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
                    logger.warn("failed to convert {} to object id: {s}", .{
                        widget.binding_context.binding.?,
                        @errorName(err),
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
                items.* = Widget.init(self.ui, self.allocator, .spacer);
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

    pub fn updateWantedSize(self: *WidgetTree, resource_manager: *ResourceManager, ui: *zero_graphics.UserInterface) ComputeWantedSizeError!void {
        try self.updateWantedSizeForWidget(&self.root, resource_manager, ui);
    }

    fn updateWantedSizeForWidget(self: *WidgetTree, widget: *Widget, resource_manager: *ResourceManager, ui: *zero_graphics.UserInterface) ComputeWantedSizeError!void {
        for (widget.children.items) |*child| {
            try self.updateWantedSizeForWidget(child, resource_manager, ui);
        }
        try self.computeWantedSize(widget, resource_manager, ui);
    }

    fn computeDefaultWantedSize(self: *WidgetTree, widget: *Widget) zero_graphics.Size {
        _ = self;
        var size = widget.get(.size_hint);
        for (widget.children.items) |child| {
            const child_size = child.getWantedSizeWithMargins();
            size.width = std.math.max(size.width, child_size.width);
            size.height = std.math.max(size.height, child_size.height);
        }
        const padding = widget.get(.paddings);
        size.width += padding.totalHorizontal();
        size.height += padding.totalVertical();
        return convertSizeToZeroG(size);
    }

    const ComputeWantedSizeError = error{OutOfMemory};
    fn computeWantedSize(self: *WidgetTree, widget: *Widget, resource_manager: *ResourceManager, ui: *zero_graphics.UserInterface) ComputeWantedSizeError!void {
        const children = widget.children.items;
        const child_count = children.len;

        // WARNING: MUST CAPTURE BY POINTER AS WE USE @fieldParentPtr!
        widget.wanted_size = switch (widget.control) {

            // TODO: Implement size computation logic here :)
            .label => |*label| blk: {
                const str = label.get(.text);

                // this prevents the collapse of a label when it's empty.
                const reference_text = if (str.get().len > 0)
                    str.get()
                else
                    "I";

                const rectangle = ui.renderer.?.measureString(ui.default_font, reference_text);

                break :blk rectangle.size();
            },

            .separator => if (child_count > 0)
                self.computeDefaultWantedSize(widget)
            else
                zero_graphics.Size{
                    .width = 5,
                    .height = 5,
                },

            .progressbar => if (child_count > 0)
                self.computeDefaultWantedSize(widget)
            else
                zero_graphics.Size{
                    .width = 256,
                    .height = 32,
                },

            .checkbox, .radiobutton => if (child_count > 0)
                self.computeDefaultWantedSize(widget)
            else
                zero_graphics.Size{
                    .width = 32,
                    .height = 32,
                },

            .slider => if (child_count > 0)
                self.computeDefaultWantedSize(widget)
            else
                zero_graphics.Size{
                    .width = 32,
                    .height = 32,
                },

            .picture => |*picture| blk: {
                const resource_id = picture.get(.image);

                if (self.ui.resources.getPtr(resource_id)) |resource| {
                    if (resource.getBitmap(resource_manager, ui)) |bmp| {
                        break :blk zero_graphics.Size{
                            .width = bmp.width,
                            .height = bmp.height,
                        };
                    }
                }

                break :blk zero_graphics.Size{
                    .width = 256,
                    .height = 256,
                };
            },

            .scrollbar => |*scrollbar| if (child_count > 0)
                self.computeDefaultWantedSize(widget)
            else blk: {
                const orientation = scrollbar.get(.orientation);

                break :blk switch (orientation) {
                    .horizontal => zero_graphics.Size{ .width = 64, .height = 24 },
                    .vertical => zero_graphics.Size{ .width = 24, .height = 64 },
                };
            },

            // .scrollview => |*scrollview| blk: {
            //     logger.err("computeWantedSize(scrollview) not implemented yet!", .{});

            //     break :blk .{
            //         .width = 256,
            //         .height = 256,
            //     };
            // },

            .stack_layout => |*stack_layout| blk: {
                const paddings = widget.get(.paddings);
                const orientation = stack_layout.get(.orientation);

                var size = zero_graphics.Size.empty;
                switch (orientation) {
                    .vertical => for (children) |*child| {
                        if (child.getActualVisibility() == .collapsed)
                            continue;
                        const child_size = child.getWantedSizeWithMargins();
                        size.width = std.math.max(size.width, child_size.width);
                        size.height += child_size.height;
                    },
                    .horizontal => for (children) |*child| {
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

            .dock_layout => |*dock_layout| blk: {
                _ = dock_layout;
                if (child_count == 0)
                    break :blk zero_graphics.Size.empty;

                var size = children[child_count - 1].getWantedSizeWithMargins();

                var i = child_count - 1;
                while (i > 0) {
                    i -= 1;
                    const child = &children[i];

                    if (child.getActualVisibility() == .collapsed)
                        continue;

                    const child_size = child.getWantedSizeWithMargins();

                    const site = child.get(.dock_site);
                    switch (site) {
                        .left, .right => {
                            // docking on either left or right side
                            // will increase the width of the wanted size
                            // and will max out the height
                            size.width += child_size.width;
                            size.height = std.math.max(size.height, child_size.height);
                        },

                        .top, .bottom => {
                            // docking on either top or bottom side
                            // will increase the height of the wanted size
                            // and will max out the width
                            size.width = std.math.max(size.width, child_size.width);
                            size.height += child_size.height;
                        },
                    }
                }

                const padding = widget.get(.paddings);
                size.width += mapToU15(padding.totalHorizontal());
                size.height += mapToU15(padding.totalVertical());

                break :blk size;
            },

            .tab_layout => blk: {
                var size = zero_graphics.Size.empty;
                for (children) |*child| {
                    const child_size = child.getWantedSizeWithMargins();
                    size.width = std.math.max(size.width, child_size.width);
                    size.height = std.math.max(size.height, child_size.height);
                }

                const padding = widget.get(.paddings);
                size.width += mapToU15(padding.totalHorizontal());
                size.height += mapToU15(padding.totalVertical());

                size.height += 32; // Tab button height

                break :blk size;
            },

            .grid_layout => |*grid| blk: {
                const row_defs = grid.get(.rows);
                const col_defs = grid.get(.columns);

                const row_count = grid.getRowCount();
                const col_count = grid.getColumnCount();

                try grid.row_heights.resize(row_count);
                try grid.column_widths.resize(col_count);

                std.mem.set(u15, grid.row_heights.items, 0);
                std.mem.set(u15, grid.column_widths.items, 0);

                var row: usize = 0;
                var col: usize = 0;
                for (children) |*child| {
                    if (child.get(.visibility) == .collapsed)
                        continue;

                    const child_size = child.getWantedSizeWithMargins();
                    grid.column_widths.items[col] = std.math.max(grid.column_widths.items[col], child_size.width);
                    grid.row_heights.items[row] = std.math.max(grid.row_heights.items[row], child_size.height);

                    col += 1;
                    if (col >= col_count) {
                        row += 1;
                        col = 0;
                        if (row >= row_count)
                            break;
                    }
                }

                for (row_defs.items) |def, i| {
                    if (def == .absolute) {
                        grid.row_heights.items[i] = def.absolute;
                    }
                }

                for (col_defs.items) |def, i| {
                    if (def == .absolute) {
                        grid.column_widths.items[i] = def.absolute;
                    }
                }

                var size = zero_graphics.Size.empty;
                for (grid.column_widths.items) |v| {
                    size.width += v;
                }
                for (grid.row_heights.items) |v| {
                    size.height += v;
                }

                const padding = widget.get(.paddings);
                size.width += mapToU15(padding.totalHorizontal());
                size.height += mapToU15(padding.totalVertical());

                break :blk size;
            },

            .button => if (child_count > 0)
                self.computeDefaultWantedSize(widget)
            else
                zero_graphics.Size{ .width = 64, .height = 24 },

            // default logic
            .panel, .spacer, .container => self.computeDefaultWantedSize(widget),

            // default logic
            else => blk: {
                const T = struct {
                    var message = std.EnumArray(protocol.WidgetType, bool).initFill(false);
                };
                if (!T.message.get(widget.control)) {
                    logger.emerg("TODO: Implement widget size computation for {s}", .{@tagName(std.meta.activeTag(widget.control))});
                    T.message.set(widget.control, true);
                }

                break :blk self.computeDefaultWantedSize(widget);
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
        const children = widget.children.items;
        const child_count = children.len;
        if (child_count == 0)
            return;

        // WARNING: MUST CAPTURE BY POINTER AS WE USE @fieldParentPtr!
        switch (widget.control) {

            // TODO: Implement layout logic here :)

            .stack_layout => |*stack_layout| {
                const stack_direction = stack_layout.get(.orientation);

                switch (stack_direction) {
                    .vertical => {
                        var rect = rectangle;
                        for (children) |*child| {
                            if (child.getActualVisibility() == .collapsed)
                                continue;

                            rect.height = child.getWantedSizeWithMargins().height;
                            self.layoutWidget(child, rect);
                            rect.y += rect.height;
                        }
                    },

                    .horizontal => {
                        var rect = rectangle;
                        for (children) |*child| {
                            if (child.getActualVisibility() == .collapsed)
                                continue;
                            rect.width = child.getWantedSizeWithMargins().width;
                            self.layoutWidget(child, rect);
                            rect.x += rect.width;
                        }
                    },
                }
            },

            .dock_layout => |*dock_layout| {
                _ = dock_layout;
                var child_area = rectangle; // will decrease for each child until last.
                for (children[0 .. child_count - 1]) |*child| {
                    if (child.getActualVisibility() == .collapsed)
                        continue;
                    const site = child.get(.dock_site);
                    const child_size = child.getWantedSizeWithMargins();
                    switch (site) {
                        .top => {
                            self.layoutWidget(child, zero_graphics.Rectangle{
                                .x = child_area.x,
                                .y = child_area.y,
                                .width = child_area.width,
                                .height = child_size.height,
                            });
                            child_area.y += child_size.height;
                            child_area.height -= child_size.height;
                        },

                        .bottom => {
                            self.layoutWidget(child, zero_graphics.Rectangle{
                                .x = child_area.x,
                                .y = child_area.y + child_area.height - child_size.height,
                                .width = child_area.width,
                                .height = child_size.height,
                            });
                            child_area.height -= child_size.height;
                        },

                        .left => {
                            self.layoutWidget(child, zero_graphics.Rectangle{
                                .x = child_area.x,
                                .y = child_area.y,
                                .width = child_size.width,
                                .height = child_area.height,
                            });
                            child_area.x += child_size.width;
                            child_area.width -= child_size.width;
                        },

                        .right => {
                            self.layoutWidget(child, zero_graphics.Rectangle{
                                .x = child_area.x + child_area.width - child_size.width,
                                .y = child_area.y,
                                .width = child_size.width,
                                .height = child_area.height,
                            });
                            child_area.width -= child_size.width;
                        },
                    }
                }

                self.layoutWidget(&children[child_count - 1], child_area);
            },

            .grid_layout => |*grid_layout| {
                const H = struct {
                    fn calculateSizes(sizes: []u15, defs: []const protocol.ColumnSizeDefinition, availableSize: u15) void {
                        var rest = availableSize;

                        var col_expander_count: u15 = 0;
                        for (defs) |def, i| {
                            switch (def) {
                                .percentage => |p| { // percentage
                                    // adjust to available size
                                    sizes[i] = @floatToInt(u15, p * @intToFloat(f32, availableSize));
                                    rest = clampSub(rest, sizes[i]);
                                },
                                // expand
                                .expand => col_expander_count += 1,
                                else => {
                                    // calculate remaining size for all expanders
                                    rest = clampSub(rest, sizes[i]);
                                },
                            }
                        }

                        // now fill up to actual count
                        for (sizes[defs.len..]) |s| {
                            rest = clampSub(rest, s);
                        }

                        for (defs) |def, i| {
                            if (def == .expand) {
                                // adjust expanded columns
                                sizes[i] = rest / col_expander_count;
                            }
                        }
                    }
                };

                H.calculateSizes(grid_layout.column_widths.items, grid_layout.get(.columns).items, rectangle.width);
                H.calculateSizes(grid_layout.row_heights.items, grid_layout.get(.rows).items, rectangle.height);

                var row: usize = 0;
                var col: usize = 0;

                var cursor = rectangle;

                var index: usize = 0;
                while (index < children.len) : (index += 1) {
                    const child = &children[index];

                    child.hidden_by_layout = false;
                    if (child.get(.visibility) == .collapsed)
                        continue;

                    cursor.width = grid_layout.column_widths.items[col];
                    cursor.height = grid_layout.row_heights.items[row];

                    self.layoutWidget(child, cursor);

                    cursor.x += cursor.width;

                    col += 1;
                    if (col >= grid_layout.column_widths.items.len) {
                        cursor.x = rectangle.x;
                        cursor.y += cursor.height;
                        row += 1;
                        col = 0;
                        if (row >= grid_layout.row_heights.items.len) {
                            index += 1; // must be manually incremented here

                            // otherwise the last visible element will be
                            // hidden by the next loop
                            break; // we are *full*
                        }
                    }
                }
                while (index < children.len) : (index += 1) {
                    children[index].hidden_by_layout = true;
                }
            },

            .scrollview => |*view| {
                _ = view;
                // TODO: This isn't the final logic

                var rect = rectangle;
                rect.width = clampSub(rect.width, scroll_bar_size);
                rect.height = clampSub(rect.height, scroll_bar_size);

                for (children) |*child| {
                    self.layoutWidget(child, rect);
                }
            },

            // default logic for "non-containers":
            .button, .label, .panel, .spacer, .picture, .container => {
                for (children) |*child| {
                    self.layoutWidget(child, rectangle);
                }
            },

            // Catcher for logic
            else => {
                const T = struct {
                    var message = std.EnumArray(protocol.WidgetType, bool).initFill(false);
                };
                if (!T.message.get(widget.control)) {
                    logger.emerg("TODO: Implement widget layout for {s}", .{@tagName(std.meta.activeTag(widget.control))});
                    T.message.set(widget.control, true);
                }

                for (children) |*child| {
                    self.layoutWidget(child, rectangle);
                }
            },
        }
    }

    pub fn processUserInterface(self: *WidgetTree, resource_manager: *ResourceManager, ui: zero_graphics.UserInterface.Builder) !void {
        try self.processUserInterfaceForWidget(&self.root, resource_manager, ui);
    }

    fn processUserInterfaceForWidget(self: *WidgetTree, widget: *Widget, resource_manager: *ResourceManager, ui: zero_graphics.UserInterface.Builder) zero_graphics.UserInterface.Builder.Error!void {
        try self.doWidgetLogic(widget, resource_manager, ui);

        for (widget.children.items) |*child| {
            try self.processUserInterfaceForWidget(child, resource_manager, ui);
        }
    }

    fn doWidgetLogic(self: *WidgetTree, widget: *Widget, resource_manager: *ResourceManager, ui: zero_graphics.UserInterface.Builder) !void {
        const rect = widget.actual_bounds;
        const hit_test_visible = widget.get(.hit_test_visible);
        // WARNING: MUST CAPTURE BY POINTER AS WE USE @fieldParentPtr!
        switch (widget.control) {

            // TODO: Implement widget logic here :)

            .container => {},

            .label => |*label| {
                const str = label.get(.text);
                try ui.label(rect, str.get(), .{
                    .id = widget,
                    .horizontal_alignment = .left,
                    .vertical_alignment = .top,
                    .hit_test_visible = hit_test_visible,
                });
            },

            .panel => |*panel| {
                _ = panel;
                try ui.panel(rect, .{
                    .id = widget,
                    .hit_test_visible = hit_test_visible,
                });
            },

            .picture => |*picture| {
                const resource_id = picture.get(.image);

                if (self.ui.resources.getPtr(resource_id)) |resource| {
                    if (resource.getBitmap(resource_manager, ui.ui)) |bmp| {
                        try ui.image(rect, bmp, .{
                            .hit_test_visible = hit_test_visible,
                        });
                    }
                }
            },

            .button => |*button| {
                const clicked = try ui.button(rect, null, null, .{
                    .id = widget,
                    .hit_test_visible = hit_test_visible,
                });
                // TODO: Process button clicks!
                if (clicked) {
                    const click_event = button.get(.on_click);
                    if (click_event != .invalid) {
                        try self.ui.triggerEvent(click_event, widget.get(.widget_name));
                    }
                }
            },

            .checkbox => |*button| {
                const is_checked = button.get(.is_checked);
                const clicked = try ui.checkBox(rect, is_checked, .{
                    .id = widget,
                    .hit_test_visible = hit_test_visible,
                });
                // TODO: Process button clicks!
                if (clicked) {
                    button.set(.is_checked, !is_checked);
                }
            },

            .radiobutton => |*button| {
                const is_checked = button.get(.is_checked);
                const clicked = try ui.radioButton(rect, is_checked, .{
                    .id = widget,
                    .hit_test_visible = hit_test_visible,
                });
                // TODO: Process button clicks!
                if (clicked)
                    logger.err("radiobutton click not implemented yet!", .{});
            },

            .scrollview => {
                var hscroll = rect;
                var vscroll = rect;
                var container = rect;

                container.width = clampSub(container.width, scroll_bar_size);
                container.height = clampSub(container.height, scroll_bar_size);

                hscroll.y += container.height;
                hscroll.width = container.width;
                hscroll.height = scroll_bar_size;

                vscroll.x += container.width;
                vscroll.width = scroll_bar_size;
                vscroll.height = container.height;

                try ui.panel(rect, .{ .id = widget });
                try ui.panel(hscroll, .{ .id = widget });
                try ui.panel(vscroll, .{ .id = widget });
            },

            // The spacer is only some empty space
            .spacer => {},

            // Layouts don't have their own "logic"
            .stack_layout, .dock_layout, .grid_layout, .flow_layout => {},

            else => {
                var fmt: [128]u8 = undefined;

                const T = struct {
                    var message = std.EnumArray(protocol.WidgetType, bool).initFill(false);
                };
                if (!T.message.get(widget.control)) {
                    logger.emerg("TODO: Implement widget logic for {s}", .{@tagName(std.meta.activeTag(widget.control))});
                    T.message.set(widget.control, true);
                }

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

const ErasedWidget = opaque {};

pub const Widget = struct {
    const Self = @This();

    usingnamespace PropertyGetSetMixin(Self, getIdentity);
    fn getIdentity(self: *const Self) *const ErasedWidget {
        return @ptrCast(*const ErasedWidget, self);
    }

    user_interface: *DunstblickUI,

    /// The list of all children of this widget.
    children: std.ArrayList(Self),

    /// The control that is contained in this widget.
    control: Control,

    /// This is a (temporary) pointer to the object that provides the values
    /// of all bound properties.
    /// It is only valid *after* `updateBindings` was invoked and will be invalidated
    /// as soon as any change to the object hierarchy is done (insertion/deletion).
    binding_source: ?*types.Object,

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

    /// If this is true, the element got hidden by the enclosing layout
    /// instead of a user choice. This might happen when it flows out of the
    /// layout.
    hidden_by_layout: bool,

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
    child_source: Property(types.ObjectList),
    child_template: Property(protocol.ResourceID),

    widget_name: Property(protocol.WidgetName),
    tab_title: Property(types.String),
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

    fn setupControl(control: *Control) void {
        inline for (std.meta.fields(Control)) |field| {
            if (control.* == @field(protocol.WidgetType, field.name)) {
                @field(control, field.name).setUp();
                return;
            }
        }
        unreachable;
    }

    pub fn init(ui: *DunstblickUI, allocator: *std.mem.Allocator, control_type: protocol.WidgetType) Widget {
        var widget = Widget{
            .user_interface = ui,
            .children = std.ArrayList(Widget).init(allocator),
            .control = initControl(control_type, allocator),
            .binding_source = null,
            .template_id = null,
            .wanted_size = undefined,
            .actual_bounds = undefined,
            .hidden_by_layout = false,

            .horizontal_alignment = .{ .value = .stretch },
            .vertical_alignment = .{ .value = .stretch },
            .margins = .{ .value = protocol.Margins.all(0) },
            .paddings = .{ .value = protocol.Margins.all(0) },
            .dock_site = .{ .value = .left },
            .visibility = .{ .value = .visible },
            .enabled = .{ .value = true },
            .hit_test_visible = .{ .value = true },
            .binding_context = .{ .value = .invalid },
            .child_source = .{ .value = types.ObjectList.init(allocator) },
            .child_template = .{ .value = .invalid },
            .widget_name = .{ .value = .invalid },
            .tab_title = .{ .value = types.String.new(allocator) },
            .size_hint = .{ .value = protocol.Size{ .width = 0, .height = 0 } },
            .left = .{ .value = 0 },
            .top = .{ .value = 0 },
        };

        setupControl(&widget.control);

        return widget;
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

    pub fn getWantedSizeWithMargins(self: Self) zero_graphics.Size {
        return addMargin(self.wanted_size, self.get(.margins));
    }

    pub fn getActualVisibility(self: Self) protocol.enums.Visibility {
        // TODO: Implement rest!
        if (self.hidden_by_layout)
            return .hidden;
        return self.get(.visibility);
    }
};

fn PropertyGetSetMixin(comptime Self: type, getErasedWidget: fn (*const Self) *const ErasedWidget) type {
    return struct {
        fn getWidget(self: *Self) *Widget {
            return @intToPtr(*Widget, @ptrToInt(getErasedWidget(self)));
        }

        fn getConstWidget(self: *const Self) *const Widget {
            return @ptrCast(*const Widget, @alignCast(@alignOf(Widget), getErasedWidget(self)));
        }

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
                const property = &@field(self, name);
                const binding_context = getConstWidget(self).binding_source;

                if (property.binding != null and binding_context != null) {
                    if (binding_context.?.getProperty(property.binding.?)) |value| {
                        if (value.convertTo(PropertyType(property_name))) |val| {
                            return val;
                        } else |err| {
                            logger.warn("binding error: converting {}) of type {s} to {s} failed: {}", .{
                                property.binding.?,
                                @tagName(std.meta.activeTag(value.*)),
                                @typeName(PropertyType(property_name)),
                                err,
                            });
                        }
                    }
                }
                return property.value;
            } else {
                @compileError("The property " ++ name ++ "does not exist on " ++ @typeName(Self));
            }
        }

        /// Sets a property
        pub fn set(self: *Self, comptime property_name: protocol.Property, value: PropertyType(property_name)) void {
            const name = @tagName(property_name);
            if (@hasField(Self, name)) {
                const property = &@field(self, name);
                const binding_context = getWidget(self).binding_source;

                if (property.binding) |object_property| {
                    if (binding_context) |bc| {
                        if (bc.getProperty(object_property)) |prop| {
                            if (types.Value.tryCreate(std.meta.activeTag(prop.*), value)) |new_val| {
                                std.debug.assert(std.meta.activeTag(new_val) == std.meta.activeTag(prop.*));

                                prop.deinit();
                                prop.* = new_val;

                                getWidget(self).user_interface.triggerPropertyChanged(bc.id, object_property, new_val) catch |err| {
                                    logger.err("Failed to trigger the property changed event for for property {} on object {}: {s}!", .{
                                        object_property,
                                        bc.id,
                                        @errorName(err),
                                    });
                                };
                            } else |err| {
                                logger.err("Failed to convert {s} to {s} for property {}: {s}", .{
                                    @typeName(PropertyType(property_name)),
                                    std.meta.activeTag(prop.*),
                                    object_property,
                                    @errorName(err),
                                });
                            }
                        } else {
                            logger.warn("Property {} is not found on the bound object!", .{object_property});
                        }
                    }
                }
                switch (PropertyType(property_name)) {
                    types.ObjectList, types.SizeList, types.String => property.value.deinit(),

                    // trivial cases don't need deinit()
                    else => {},
                }
                property.value = value;
            } else {
                @compileError("The property " ++ name ++ "does not exist on " ++ @typeName(Self));
            }
        }
    };
}

fn ControlMixin(comptime Self: type) type {
    return struct {
        pub usingnamespace PropertyGetSetMixin(Self, erasedWidget);

        fn erasedWidget(self: *const Self) *const ErasedWidget {
            return @ptrCast(*const ErasedWidget, widgetConst(self));
        }

        pub fn widget(self: *Self) *Widget {

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

            const ctrl = @ptrCast(*Control, @alignCast(@alignOf(Control), self));
            return @fieldParentPtr(Widget, "control", ctrl);
        }

        pub fn widgetConst(self: *const Self) *const Widget {
            // This is safe as we only compute some offsets
            return widget(@intToPtr(*Self, @ptrToInt(self)));
        }
    };
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
    spacer: Spacer,
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
        usingnamespace ControlMixin(Self);

        dummy: u32, // prevent zero-sizing

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .dummy = 0,
            };
        }

        pub fn setUp(self: *Self) void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Spacer = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        dummy: u32, // prevent zero-sizing

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .dummy = 0,
            };
        }

        pub fn setUp(self: *Self) void {
            self.widget().set(.hit_test_visible, false);
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Button = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        on_click: Property(protocol.EventID),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .on_click = .{ .value = .invalid },
            };
        }

        pub fn setUp(self: *Self) void {
            // self.widget().set(.size_hint, .{});
            self.widget().set(.margins, protocol.Margins.all(8));
            self.widget().set(.paddings, protocol.Margins.all(8));
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Label = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        text: Property(types.String),
        font_family: Property(protocol.enums.Font),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .text = .{ .value = types.String.new(allocator) },
                .font_family = .{ .value = .sans },
            };
        }

        pub fn setUp(self: *Self) void {
            self.widget().set(.margins, protocol.Margins.all(8));
            self.widget().set(.horizontal_alignment, .center);
            self.widget().set(.vertical_alignment, .middle);
            self.widget().set(.hit_test_visible, false);
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Picture = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        image: Property(protocol.ResourceID),
        image_scaling: Property(protocol.enums.ImageScaling),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .image = .{ .value = .invalid },
                .image_scaling = .{ .value = .stretch },
            };
        }

        pub fn setUp(self: *Self) void {
            self.widget().set(.hit_test_visible, false);
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const CheckBox = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        is_checked: Property(bool),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .is_checked = .{ .value = false },
            };
        }

        pub fn setUp(self: *Self) void {
            self.widget().set(.horizontal_alignment, .left);
            self.widget().set(.vertical_alignment, .middle);
            self.widget().set(.margins, protocol.Margins.all(8));
            self.widget().set(.paddings, protocol.Margins.all(8));
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const RadioButton = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        is_checked: Property(bool),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .is_checked = .{ .value = false },
            };
        }

        pub fn setUp(self: *Self) void {
            self.widget().set(.horizontal_alignment, .left);
            self.widget().set(.vertical_alignment, .middle);
            self.widget().set(.margins, protocol.Margins.all(8));
            self.widget().set(.paddings, protocol.Margins.all(8));
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const ScrollBar = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        minimum: Property(f32),
        maximum: Property(f32),
        value: Property(f32),
        orientation: Property(protocol.enums.Orientation),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .minimum = .{ .value = 0.0 },
                .maximum = .{ .value = 100.0 },
                .value = .{ .value = 25.0 },
                .orientation = .{ .value = .horizontal },
            };
        }

        pub fn setUp(self: *Self) void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const Slider = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        minimum: Property(f32),
        maximum: Property(f32),
        value: Property(f32),
        orientation: Property(protocol.enums.Orientation),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .minimum = .{ .value = 0.0 },
                .maximum = .{ .value = 100.0 },
                .value = .{ .value = 0.0 },
                .orientation = .{ .value = .horizontal },
            };
        }

        pub fn setUp(self: *Self) void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const ProgressBar = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        minimum: Property(f32),
        maximum: Property(f32),
        value: Property(f32),
        orientation: Property(protocol.enums.Orientation),
        display_progress_style: Property(protocol.enums.DisplayProgressStyle),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .minimum = .{ .value = 0.0 },
                .maximum = .{ .value = 100.0 },
                .value = .{ .value = 0.0 },
                .orientation = .{ .value = .horizontal },
                .display_progress_style = .{ .value = .percent },
            };
        }

        pub fn setUp(self: *Self) void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const StackLayout = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        orientation: Property(protocol.enums.StackDirection),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .orientation = .{ .value = .vertical },
            };
        }

        pub fn setUp(self: *Self) void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const TabLayout = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        selected_index: Property(i32),

        pub fn init(allocator: *std.mem.Allocator) Self {
            _ = allocator;
            return Self{
                .selected_index = .{ .value = 0 },
            };
        }

        pub fn setUp(self: *Self) void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }
    };

    pub const GridLayout = struct {
        const Self = @This();
        usingnamespace ControlMixin(Self);

        rows: Property(types.SizeList),
        columns: Property(types.SizeList),

        row_heights: std.ArrayList(u15),
        column_widths: std.ArrayList(u15),

        pub fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .rows = .{ .value = types.SizeList.init(allocator) },
                .columns = .{ .value = types.SizeList.init(allocator) },
                .row_heights = std.ArrayList(u15).init(allocator),
                .column_widths = std.ArrayList(u15).init(allocator),
            };
        }

        pub fn setUp(self: *Self) void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            deinitAllProperties(Self, self);
            self.* = undefined;
        }

        pub fn getRowCount(self: *const Self) u15 {
            const rows = self.get(.rows);
            const columns = self.get(.columns);
            const children = self.widgetConst().children.items;
            return if (rows.items.len != 0)
                mapToU15(rows.items.len)
            else if (columns.items.len == 0)
                1
            else
                mapToU15((children.len + columns.items.len - 1) / columns.items.len);
        }

        pub fn getColumnCount(self: *const Self) u15 {
            const rows = self.get(.rows);
            const columns = self.get(.columns);
            const children = self.widgetConst().children.items;
            return if (columns.items.len != 0)
                mapToU15(columns.items.len)
            else if (rows.items.len == 0)
                1
            else
                mapToU15((children.len + rows.items.len - 1) / rows.items.len);
        }
    };
};

fn mapToU15(value: anytype) u15 {
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

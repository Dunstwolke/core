const std = @import("std");

usingnamespace @import("types.zig");
usingnamespace @import("object.zig");

pub const UIContext = struct {
    allocator: *std.mem.Allocator,
    objects: ObjectStore,
    root: ?Widget,

    pub fn init(allocator: *std.mem.Allocator) UIContext {
        return UIContext{
            .allocator = allocator,
            .objects = ObjectStore.init(allocator),
            .root = null,
        };
    }

    pub fn deinit(ctx: UIContext) void {
        if (ctx.root) |root| {
            root.deinit();
        }
        ctx.objects.deinit();
    }
};

pub const Widget = struct {
    // fields follow below
    const Properties = struct {
        // generic layouting properties
        horizontalAlignment: HAlignment = .stretch,
        verticalAlignment: VAlignment = .stretch,
        visibility: Visibility = .visible,
        margins: Margins = Margins.initAll(4),
        paddings: Margins = Margins.zero,
        enabled: bool = true,
        sizeHint: Size = Size{ .width = 0, .height = 0 },
        hitTestVisible: bool = true,

        // Automatic child generation
        childSource: ?ObjectList = null,
        childTemplate: ?ResourceID = null,

        /// stores either a ResourceID or a property binding
        /// for the bindingSource. If the property is bound,
        /// it will bind to the parent bindingSource instead
        /// of the own bindingSource.
        /// see the implementation of @ref updateBindings
        bindingContext: ?ObjectID = null,

        // dock layout
        dockSite: DockSite = DockSite.top,

        // tab layout
        tabTitle: []const u8 = "Tab Page",

        // canvas layout
        left: i32 = 0,
        top: i32 = 0,
    };

    /// contains the binding information of each property in
    /// Properties.
    const Bindings = struct {
        horizontalAlignment: ?PropertyID = null,
        verticalAlignment: ?PropertyID = null,
        visibility: ?PropertyID = null,
        margins: ?PropertyID = null,
        paddings: ?PropertyID = null,
        enabled: ?PropertyID = null,
        sizeHint: ?PropertyID = null,
        hitTestVisible: ?PropertyID = null,
        childSource: ?PropertyID = null,
        childTemplate: ?PropertyID = null,
        bindingContext: ?PropertyID = null,
        dockSite: ?PropertyID = null,
        tabTitle: ?PropertyID = null,
        left: ?PropertyID = null,
        top: ?PropertyID = null,
    };

    comptime {
        var all = true;
        for (std.meta.fields(Properties)) |fld| {
            if (!@hasField(Bindings, fld.name)) {
                all = false;
                @compileLog("Missing field in Widget.Bindings: " ++ fld.name);
            }
            if (!@hasField(PropertyName, fld.name)) {
                all = false;
                @compileLog("Field " ++ fld.name ++ " does not have a corresponding property defined in the enumeration!");
            }
        }
        if (!all)
            @compileError("Not all fields of Widget.Properties are available in Widget.Bindings!");
    }

    comptime {
        var all = true;
        for (std.meta.fields(Bindings)) |fld| {
            if (fld.field_type != ?PropertyID)
                @compileError("Invalid type for field '" ++ fld.name ++ "': " ++ @typeName(fld.field_type));
            if (!@hasField(Properties, fld.name)) {
                all = false;
                @compileLog("Missing field in Widget.Properties: " ++ fld.name);
            }
        }
        if (!all)
            @compileError("Not all fields of Widget.Bindings are available in Widget.Properties!");
    }

    const WidgetClass = union(WidgetType) {
        button: void,
        label: void,
        combobox: void,
        treeview: void,
        listbox: void,
        picture: void,
        textbox: void,
        checkbox: void,
        radiobutton: void,
        scrollview: void,
        scrollbar: void,
        slider: void,
        progressbar: void,
        spinedit: void,
        separator: void,
        spacer: void,
        panel: void,
        tab_layout: void,
        canvas_layout: void,
        flow_layout: void,
        grid_layout: void,
        dock_layout: void,
        stack_layout: void,

        fn new(t: WidgetType) WidgetClass {
            return undefined;
        }
    };

    // FIELDS START HERE

    /// upwards reference to the UI context
    /// that created this widget.
    context: *UIContext,

    /// set by the deserializer on the root widget
    /// to the resource this widget was loaded from.
    templateId: ?ResourceID = null,

    /// contains all child widgets
    children: std.ArrayList(Widget),

    /// contains all script-definable properties of a widget
    properties: Properties,

    /// contains all binding overides for properties
    bindings: Bindings,

    /// Stores the type of this widget as well as some additional
    /// fields if necessary.
    class: WidgetClass,

    // layouting and rendering

    /// the space the widget says it needs to have.
    /// this is a hint to each layouting algorithm to auto-size the widget
    /// accordingly.
    wantedSize: Size = undefined,

    /// the position of the widget on the screen after layouting.
    /// NOTE: this does not include the margins of the widget!
    actualBounds: Rectangle = undefined,

    /// if set to `true`, this widget has been hidden by the
    /// layout, not by the user.
    hiddenByLayout: bool = false,

    /// stores the raw object pointer to which properties will bind.
    /// this must be refreshed after any changes to the object hierarchy!
    bindingSource: ?*Object = null,

    pub fn init(context: *UIContext, class: WidgetType) Widget {
        return Widget{
            .context = context,
            .properties = Properties{}, // all default
            .bindings = Bindings{}, // all default
            .children = std.ArrayList(Widget).init(context.allocator),
            .class = WidgetClass.new(class),
        };
    }

    pub fn deinit(widget: Widget) void {
        widget.children.deinit();
    }

    /// helper function that returns the type of a property by name
    fn PropertyType(comptime property: PropertyName) type {
        return std.meta.fieldInfo(Properties, @tagName(property)).field_type;
    }

    /// Gets a property with respect to bindings.
    pub fn get(widget: Widget, comptime property: PropertyName) PropertyType(property) {
        const name = @tagName(property);

        if (widget.bindingSource) |source| {
            if (@field(widget.bindings, name)) |binding| {
                if (source.getProperty(binding)) |val| {
                    // if we have both a bindingSource *and* a binding that exists,
                    // return the value of that property converted to the type of
                    // the wanted property.
                    // TODO: This may leak string or list memory?!
                    //       Maybe use an arena allocator for this!
                    if (val.convertTo(Type.from(PropertyType(property)))) |converted| {
                        return converted.get(PropertyType(property));
                    } else |err| {
                        // well, this is a binding error and we ignore those in general
                        std.debug.warn("binding failed: {}", .{err});
                    }
                }
            }
        }
        return @field(widget.properties, name);
    }

    /// Sets a property with respect to bindings.
    pub fn set(widget: *Widget, comptime property: PropertyName, value: PropertyType(property)) !void {
        const name = @tagName(property);
        if (widget.bindingSource) |source| {
            if (@field(widget.bindings, name)) |binding| {
                if (source.getPropertyType(binding)) |proptype| {
                    // if we have both a bindingSource *and* a binding that exists,
                    // convert the current value to the property type of the object.
                    // TODO: This may leak string or list memory?!
                    //       Maybe use an arena allocator for this!
                    try source.setProperty(binding, try Value.initFrom(value).convertTo(proptype));
                    return;
                }
            }
        }
        @field(widget.properties, name) = value;
    }

    /// This is the first stage of the UI update process:
    /// It updates the bindingSource reference for each widget
    /// recursively.
    /// `parentBindingSource` is the object to which the parent binds its
    /// properties.
    fn updateBindings(widget: *Widget, parentBindingSource: ?*Object) void {
        // STAGE 1: Update the current binding source

        // if we have a bindingSource of the parent available:
        if (parentBindingSource != null and widget.bindings.bindingContext != null) {
            // check if the parent source has the property
            // we bind our bindingContext to and if yes,
            // bind to it
            if (parentBindingSource.?.getProperty(widget.bindings.bindingContext.?)) |prop| {
                widget.bindingSource = prop.object.resolve(widget.context.objects);
            } else {
                widget.bindingSource = null;
            }
        } else {
            // otherwise check if our bindingContext has a valid resourceID and
            // load that resource reference:
            if (widget.properties.bindingContext) |objref| {
                widget.bindingSource = objref.resolve(widget.context.objects);
            } else {
                widget.bindingSource = parentBindingSource;
            }
        }

        // STAGE 2: Update child widgets.
        // TODO: Reimplement child template instantiation!
        // if(auto ct = childTemplate.get(this); not ct.is_null())
        // {
        //   // if we have a child binding, update the child list
        //   auto list = childSource.get(this);
        //   if(this->children.size() != list.size())
        //     this->children.resize(list.size());
        //   for(size_t i = 0; i < list.size(); i++)
        //   {
        //     auto & child = this->children[i];
        //     if(not child or (child->templateID != ct)) {
        //       child = load_widget(ct);
        //     }

        //     // update the children with the list as
        //     // parent item:
        //     // this rebinds the logic such that each child
        //     // will bind to the list item instead
        //     // of the actual binding context :)
        //     child->updateBindings(list[i]);
        //   }
        // }
        // else
        {
            // if not, just update all children regulary
            for (widget.children.toSlice()) |*child| {
                child.updateBindings(widget.bindingSource);
            }
        }
    }

    /// second stage of the updating process:
    /// calculating space constraints.
    /// this requires to first update all children and then call the
    /// widget-specific constraint calculator
    fn updateWantedSize(widget: *Widget) void {
        for (widget.children.toSlice()) |*child| {
            child.updateWantedSize();
        }
        widget.wantedSize = widget.calculateWantedSize();
    }

    fn layout(widget: *Widget, _bounds: Rectangle) void {
        const margins = widget.get(.margins);
        const bounds = Rectangle{
            .x = _bounds.x + @intCast(isize, margins.left),
            .y = _bounds.y + @intCast(isize, margins.top),
            .width = std.math.max(0, _bounds.width - margins.totalHorizontal()), // safety check against underflow
            .height = std.math.max(0, _bounds.height - margins.totalVertical()),
        };

        const wanted_size = widget.wantedSize;

        var target: Rectangle = undefined;
        switch (widget.get(.horizontalAlignment)) {
            .stretch => {
                target.width = bounds.width;
                target.x = 0;
            },
            .left => {
                target.width = std.math.min(wanted_size.width, bounds.width);
                target.x = 0;
            },
            .center => {
                target.width = std.math.min(wanted_size.width, bounds.width);
                target.x = @intCast(isize, (bounds.width - target.width) / 2);
            },
            .right => {
                target.width = std.math.min(wanted_size.width, bounds.width);
                target.x = @intCast(isize, bounds.width - target.width);
            },
        }
        target.x += bounds.x;

        switch (widget.get(.verticalAlignment)) {
            .stretch => {
                target.height = bounds.height;
                target.y = 0;
            },
            .top => {
                target.height = std.math.min(wanted_size.height, bounds.height);
                target.y = 0;
            },
            .middle => {
                target.height = std.math.min(wanted_size.height, bounds.height);
                target.y = @intCast(isize, (bounds.height - target.height) / 2);
            },
            .bottom => {
                target.height = std.math.min(wanted_size.height, bounds.height);
                target.y = @intCast(isize, bounds.height - target.height);
            },
        }
        target.y += bounds.y;

        widget.actualBounds = target;

        const paddings = widget.get(.paddings);
        const childArea = Rectangle{
            .x = widget.actualBounds.x + @intCast(isize, paddings.left),
            .y = widget.actualBounds.y + @intCast(isize, paddings.top),
            .width = widget.actualBounds.width - paddings.totalHorizontal(),
            .height = widget.actualBounds.height - paddings.totalVertical(),
        };

        widget.layoutChildren(childArea);
    }

    /// This function will lay out all children in this widget.
    /// It's primary function is to allow different kinds of layout.
    fn layoutChildren(widget: *Widget, rect: Rectangle) void {
        // TODO: Implement inheritance
        for (widget.children.toSlice()) |*child| {
            child.layout(rect);
        }
    }

    /// this function calculcates the size this widget
    /// wants to take in the layout.
    /// this calculcate usually requires the `wantedSize` of
    /// children to be set.
    fn calculateWantedSize(widget: *Widget) Size {
        // TODO: Implement inheritance
        const shint = widget.get(.sizeHint);

        if (widget.children.len == 0)
            return shint;

        var size = Size{ .width = 0, .height = 0 };
        for (widget.children.toSlice()) |child| {
            const wswm = child.getWantedSizeWithMargins();
            size.width = std.math.max(size.width, wswm.width);
            size.height = std.math.max(size.height, wswm.height);
        }

        size.width = std.math.max(size.width, shint.width);
        size.height = std.math.max(size.height, shint.height);

        return size;
    }

    /// Returns the wantedSize field with added margins
    fn getWantedSizeWithMargins(widget: Widget) Size {
        const margins = widget.get(.margins);
        return Size{
            .width = widget.wantedSize.width + margins.totalHorizontal(),
            .height = widget.wantedSize.height + margins.totalVertical(),
        };
    }
};

test "Widget Bindings" {
    const allocator = std.heap.direct_allocator;

    var obj = Object.init(allocator, ObjectID.init(1));
    defer obj.deinit();

    // this is unsafe, but the property system doesn't use
    // the UIContext stored in the widget anyways.
    // The context would be required though if updateBindings is used.
    var ctx: UIContext = undefined;

    var widget = Widget.init(&ctx, .panel);
    defer widget.deinit();

    const pid = PropertyID.init(42);

    try obj.setProperty(pid, Value{ .integer = 100 });

    widget.properties.left = 10;

    std.testing.expectEqual(@as(i32, 10), widget.get(.left));

    widget.bindingSource = &obj;
    widget.bindings.left = pid;

    std.testing.expectEqual(@as(i32, 100), widget.get(.left));
    try widget.set(.left, 50);

    std.testing.expectEqual(@as(i32, 50), obj.getProperty(pid).?.integer);
}

test "Widget.updateBindings" {
    const allocator = std.heap.direct_allocator;

    var context = UIContext.init(allocator);
    defer context.deinit();

    const oid1 = ObjectID.init(1); // base object
    const oid2 = ObjectID.init(2); // used to test "reference by unbound bindingContext"
    const oid3 = ObjectID.init(3); // used to test "reference by bound bindingContext"

    const pid = PropertyID.init(2);

    const obj1 = try context.objects.addOrGet(oid1);
    try obj1.setProperty(pid, Value{ .object = oid3 });

    const obj2 = try context.objects.addOrGet(oid2);
    const obj3 = try context.objects.addOrGet(oid3);

    var widget = Widget.init(&context, .panel);
    defer widget.deinit();

    // TEST UNBOUND PROPERTIES

    widget.properties.bindingContext = null; // unset binding context

    widget.updateBindings(null); // no context, no binding => no source
    std.testing.expectEqual(@as(?*Object, null), widget.bindingSource);

    widget.updateBindings(obj1); // context, no binding => context
    std.testing.expectEqual(@as(?*Object, obj1), widget.bindingSource);

    widget.properties.bindingContext = oid2; // set binding context without binding

    widget.updateBindings(null); // no context, binding => binding source
    std.testing.expectEqual(@as(?*Object, obj2), widget.bindingSource);

    widget.updateBindings(obj1); // context, binding => binding source
    std.testing.expectEqual(@as(?*Object, obj2), widget.bindingSource);

    // TEST BOUND PROPERTIES
    widget.bindings.bindingContext = pid; // bind to "property"

    widget.properties.bindingContext = null; // unset binding context

    widget.updateBindings(null); // no context, no binding => no source
    std.testing.expectEqual(@as(?*Object, null), widget.bindingSource);

    widget.updateBindings(obj1); // context, no binding => indirect binding source
    std.testing.expectEqual(@as(?*Object, obj3), widget.bindingSource);

    widget.properties.bindingContext = oid2; // set binding context with binding

    widget.updateBindings(null); // no context, binding => binding source
    std.testing.expectEqual(@as(?*Object, obj2), widget.bindingSource);

    widget.updateBindings(obj1); // context, binding => indirect source
    std.testing.expectEqual(@as(?*Object, obj3), widget.bindingSource);
}

test "Widget.wantedSize" {
    const allocator = std.heap.direct_allocator;

    var context = UIContext.init(allocator);
    defer context.deinit();

    var widget = Widget.init(&context, .panel);
    defer widget.deinit();

    widget.updateWantedSize();

    std.testing.expectEqual(Size{ .width = 0, .height = 0 }, widget.wantedSize);
}

test "Widget.layout (margins)" {
    const allocator = std.heap.direct_allocator;

    var context = UIContext.init(allocator);
    defer context.deinit();

    var widget = Widget.init(&context, .panel);
    defer widget.deinit();

    widget.properties.margins = Margins{
        .left = 5,
        .right = 10,
        .top = 15,
        .bottom = 20,
    };

    widget.updateWantedSize();

    widget.layout(Rectangle{
        .x = 0,
        .y = 0,
        .width = 200,
        .height = 100,
    });

    std.testing.expectEqual(Rectangle{
        .x = 5,
        .y = 15,
        .width = 185,
        .height = 65,
    }, widget.actualBounds);
}

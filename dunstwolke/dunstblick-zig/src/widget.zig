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
        bindingContext: ?ObjectRef = null,

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

    // layouting and rendering

    /// the space the widget says it needs to have.
    /// this is a hint to each layouting algorithm to auto-size the widget
    /// accordingly.
    wantedSize: Size = undefined,

    /// the position of the widget on the screen after layouting
    /// NOTE: this does not include the margins of the widget!
    actualBounds: Rectangle = undefined,

    /// if set to `true`, this widget has been hidden by the
    /// layout, not by the user.
    hiddenByLayout: bool = false,

    /// stores the raw object pointer to which properties will bind.
    /// this must be refreshed after any changes to the object hierarchy!
    bindingSource: ?*Object = null,

    pub fn init(context: *UIContext) Widget {
        return Widget{
            .context = context,
            .properties = Properties{}, // all default
            .bindings = Bindings{}, // all default
            .children = std.ArrayList(Widget).init(context.allocator),
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
    pub fn get(widget: Widget, comptime property: PropertyName) !PropertyType(property) {
        const name = @tagName(property);

        if (widget.bindingSource) |source| {
            if (@field(widget.bindings, name)) |binding| {
                if (source.getProperty(binding)) |val| {
                    // if we have both a bindingSource *and* a binding that exists,
                    // return the value of that property converted to the type of
                    // the wanted property.
                    // TODO: This may leak string or list memory?!
                    //       Maybe use an arena allocator for this!
                    return (try val.convertTo(Type.from(PropertyType(property)))).get(PropertyType(property));
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
};

test "Widget Bindings" {
    const allocator = std.heap.direct_allocator;

    var obj = Object.init(allocator, ObjectID.init(1));
    defer obj.deinit();

    // this is unsafe, but the property system doesn't use
    // the UIContext stored in the widget anyways.
    // The context would be required though if updateBindings is used.
    var ctx: UIContext = undefined;

    var widget = Widget.init(&ctx);
    defer widget.deinit();

    const pid = PropertyID.init(42);

    try obj.setProperty(pid, Value{ .integer = 100 });

    widget.properties.left = 10;

    std.testing.expectEqual(@as(i32, 10), try widget.get(.left));

    widget.bindingSource = &obj;
    widget.bindings.left = pid;

    std.testing.expectEqual(@as(i32, 100), try widget.get(.left));
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
    try obj1.setProperty(pid, Value{ .object = ObjectRef{ .id = oid3 } });

    const obj2 = try context.objects.addOrGet(oid2);
    const obj3 = try context.objects.addOrGet(oid3);

    var widget = Widget.init(&context);
    defer widget.deinit();

    // TEST UNBOUND PROPERTIES

    widget.properties.bindingContext = null; // unset binding context

    widget.updateBindings(null); // no context, no binding => no source
    std.testing.expectEqual(@as(?*Object, null), widget.bindingSource);

    widget.updateBindings(obj1); // context, no binding => context
    std.testing.expectEqual(@as(?*Object, obj1), widget.bindingSource);

    widget.properties.bindingContext = ObjectRef{ .id = oid2 }; // set binding context without binding

    widget.updateBindings(null); // no context, binding => binding source
    std.testing.expectEqual(@as(?*Object, obj2), widget.bindingSource);

    widget.updateBindings(obj1); // context, binding => binding source
    std.testing.expectEqual(@as(?*Object, obj2), widget.bindingSource);

    // TEST BOUND PROPERTIES
    widget.bindings.bindingContext = pid; // bind to "property 2"

    widget.properties.bindingContext = null; // unset binding context

    widget.updateBindings(null); // no context, no binding => no source
    std.testing.expectEqual(@as(?*Object, null), widget.bindingSource);

    widget.updateBindings(obj1); // context, no binding => indirect binding source
    std.testing.expectEqual(@as(?*Object, obj3), widget.bindingSource);

    widget.properties.bindingContext = ObjectRef{ .id = oid2 }; // set binding context without binding

    widget.updateBindings(null); // no context, binding => binding source
    std.testing.expectEqual(@as(?*Object, obj2), widget.bindingSource);

    widget.updateBindings(obj1); // context, binding => indirect source
    std.testing.expectEqual(@as(?*Object, obj3), widget.bindingSource);
}

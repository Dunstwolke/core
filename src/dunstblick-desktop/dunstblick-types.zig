const std = @import("std");

/// The name of a property that can be bound.
pub const PropertyId = enum(u32) { invalid = 0, _ };
pub const ResourceId = enum(u32) { invalid = 0, _ };
pub const EventId = enum(u32) { invalid = 0, _ };
pub const WidgetId = enum(u32) { invalid = 0, _ };
pub const ObjectId = enum(u32) { invalid = 0, _ };

/// A point in the 2D plane.
pub const Point = struct {
    const Self = @This();

    /// horizontal offset to the left border.
    x: i16,

    /// vertical offset to the top border.
    y: i16,

    pub fn eql(self: Self, other: Self) bool {
        return std.meta.eql(self, other);
    }
};

pub const Size = struct {
    const Self = @This();

    /// vertical expansion of the rectangle in display units.
    width: u15,

    /// horizontal expansion of the rectangle in display units.
    height: u15,

    pub fn eql(self: Self, other: Self) bool {
        return std.meta.eql(self, other);
    }
};

pub const Margin = struct {
    const Self = @This();

    left: u16,
    top: u16,
    right: u16,
    bottom: u16,

    pub fn all(v: u16) Self {
        return Self{
            .left = v,
            .top = v,
            .right = v,
            .bottom = v,
        };
    }

    pub fn eql(self: Self, other: Self) bool {
        return std.meta.eql(self, other);
    }
};

pub const Color = extern struct {
    const Self = @This();

    r: u8,
    g: u8,
    b: u8,
    a: u8 = 0xFF,

    pub fn eql(self: Self, other: Self) bool {
        return @bitCast(u32, self) == @bitCast(u32, other);
    }
};

/// A portion of the 2D plane.
pub const Rectangle = struct {
    /// horizontal offset to the left border.
    x: i16,

    /// vertical offset to the top border.
    y: i16,

    /// horizontal expansion of the rectangle in display units.
    width: u15,

    /// vertical expansion of the rectangle in display units.
    height: u15,
};

/// A cursor
pub const Cursor = enum {
    /// The arrow is the default cursor that signals that the hovered location is nothing special
    arrow,
    /// The hand signals a clickable location.
    hand,
    /// The I-beam signals that a text input is possible when clicking.
    ibeam,
    /// The wait cursor signals the user that they have to wait and the program is not response right now
    wait,
    /// Crosshair signals that the user can select a position
    crosshair,
    /// The arrow with wait symbol signals the user that a background task is not finished yet, but the program is still responsive
    wait_arrow,
    /// A double arrow pointing northwest and southeast, signalling a resize option in that direction.
    size_nwse,
    /// A double arrow pointing northeast and southwest, signalling a resize option in that direction.
    size_nesw,
    /// A double arrow pointing west and east, signalling a resize option in that direction.
    size_we,
    /// A double arrow pointing north and south, signalling a resize option in that direction.
    size_ns,
    /// A four pointed arrow pointing north, south, east, and west, signalling a move option in all directions.
    size_all,
    /// A slashes circle, signalling that the currentl hovered position has a forbidden action
    no,
};

pub const TextAlign = enum(u2) {
    left = 0,
    center = 1,
    right = 2,
    block = 3,
};

pub const ThemeColor = enum(u2) {
    background = 0,
    input_field = 1,
    highlight = 2,
    checkered = 3,
};

pub const LineStyle = enum(u1) {
    /// A small border with a 3D effect, looks like a welding around the object
    crease = 0,
    /// A small border with a 3D effect, looks like a welding around the object
    edge = 1,
};

pub const Bevel = enum(u3) {
    /// A small border with a 3D effect, looks like a welding around the object
    edge = 0,
    /// A small border with a 3D effect, looks like a crease around the object
    crease = 1,
    /// A small border with a 3D effect, looks like the object is raised up from the surroundings
    raised = 2,
    /// A small border with a 3D effect, looks like the object is sunken into the surroundings
    sunken = 3,
    /// The *deep* 3D border
    input_field = 4,
    /// Normal button outline
    button_default = 5,
    /// Pressed button outline
    button_pressed = 6,
    /// Active button outline, not pressed
    button_active = 7,
};

pub const Enumeration = enum(u8) {
    none = 0,
    left = 1,
    center = 2,
    right = 3,
    top = 4,
    middle = 5,
    bottom = 6,
    stretch = 7,
    expand = 8,
    _auto = 9,
    yesno = 10,
    truefalse = 11,
    onoff = 12,
    visible = 13,
    hidden = 14,
    collapsed = 15,
    vertical = 16,
    horizontal = 17,
    sans = 18,
    serif = 19,
    monospace = 20,
    percent = 21,
    absolute = 22,
    zoom = 23,
    contain = 24,
    cover = 25,
};

pub const VAlignment = enum(u8) {
    stretch = @enumToInt(Enumeration.stretch),
    top = @enumToInt(Enumeration.top),
    middle = @enumToInt(Enumeration.middle),
    bottom = @enumToInt(Enumeration.bottom),
};

pub const DockSite = enum(u8) {
    top = @enumToInt(Enumeration.top),
    bottom = @enumToInt(Enumeration.bottom),
    left = @enumToInt(Enumeration.left),
    right = @enumToInt(Enumeration.right),
};

pub const StackDirection = enum(u8) {
    vertical = @enumToInt(Enumeration.vertical),
    horizontal = @enumToInt(Enumeration.horizontal),
};

pub const Orientation = enum(u8) {
    horizontal = @enumToInt(Enumeration.horizontal),
    vertical = @enumToInt(Enumeration.vertical),
};

pub const UIFont = enum(u8) {
    sans = @enumToInt(Enumeration.sans),
    serif = @enumToInt(Enumeration.serif),
    monospace = @enumToInt(Enumeration.monospace),
};

pub const BooleanFormat = enum(u8) {
    truefalse = @enumToInt(Enumeration.truefalse),
    yesno = @enumToInt(Enumeration.yesno),
    onoff = @enumToInt(Enumeration.onoff),
};

pub const HAlignment = enum(u8) {
    stretch = @enumToInt(Enumeration.stretch),
    left = @enumToInt(Enumeration.left),
    center = @enumToInt(Enumeration.center),
    right = @enumToInt(Enumeration.right),
};

pub const ImageScaling = enum(u8) {
    none = @enumToInt(Enumeration.none),
    center = @enumToInt(Enumeration.center),
    stretch = @enumToInt(Enumeration.stretch),
    zoom = @enumToInt(Enumeration.zoom),
    contain = @enumToInt(Enumeration.contain),
    cover = @enumToInt(Enumeration.cover),
};

pub const DisplayProgressStyle = enum(u8) {
    none = @enumToInt(Enumeration.none),
    percent = @enumToInt(Enumeration.percent),
    absolute = @enumToInt(Enumeration.absolute),
};

pub const Visibility = enum(u8) {
    visible = @enumToInt(Enumeration.visible),
    collapsed = @enumToInt(Enumeration.collapsed),
    hidden = @enumToInt(Enumeration.hidden),
};

pub const Type = enum(u8) {
    invalid = 0,
    integer = 1,
    number = 2,
    string = 3,
    enumeration = 4,
    margins = 5,
    color = 6,
    size = 7,
    point = 8,
    resource = 9,
    boolean = 10,
    size_list = 11,
    object = 12,
    object_list = 13,
    event = 14,
    name = 15,
};

fn DynamicArray(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        allocator: *std.mem.Allocator,

        pub fn init(allocator: *std.mem.Allocator, items: []const T) !Self {
            return Self{
                .allocator = allocator,
                .items = try allocator.dupe(T, items),
            };
        }

        pub fn eql(self: Self, other: Self) bool {
            const maybe_has_eql = (@typeInfo(T) == .Struct) or
                (@typeInfo(T) == .Enum) or
                (@typeInfo(T) == .Union);

            if (maybe_has_eql and @hasDecl(T, "eql")) {
                if (self.items.len != other.items.len)
                    return false;
                for (self.items) |item, i| {
                    if (!item.eql(other.items[i]))
                        return false;
                }
                return true;
            } else {
                return std.mem.eql(T, self.items, other.items);
            }
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
            self.* = undefined;
        }
    };
}

pub const String = DynamicArray(u8);
pub const ObjectList = DynamicArray(ObjectId);
pub const SizeList = DynamicArray(SizeDef);

pub const Value = union(Type) {
    const Self = @This();

    invalid: void,
    integer: i32,
    number: f32,
    string: String,
    enumeration: u8,
    margins: Margin,
    color: Color,
    size: Size,
    point: Point,
    resource: ResourceId,
    boolean: bool,
    size_list: SizeList,
    object: ObjectId,
    object_list: ObjectList,
    event: EventId,
    name: WidgetId,

    pub fn eql(self: Self, other: Self) bool {
        if (@as(Type, self) != @as(Type, other))
            return false;
        return switch (self) {
            .invalid => unreachable,
            .integer => |v| (v == other.integer),
            .number => |v| (v == other.number),
            .string => |v| v.eql(other.string),
            .enumeration => |v| (v == other.enumeration),
            .margins => |v| v.eql(other.margins),
            .color => |v| v.eql(other.color),
            .size => |v| v.eql(other.size),
            .point => |v| v.eql(other.point),
            .resource => |v| (v == other.resource),
            .boolean => |v| (v == other.boolean),
            .size_list => |v| v.eql(other.size_list),
            .object => |v| (v == other.object),
            .object_list => |v| v.eql(other.object_list),
            .event => |v| (v == other.event),
            .name => |v| (v == other.name),
        };
    }

    pub fn dupe(self: Self, allocator: *std.mem.Allocator) !Self {
        return switch (self) {
            .invalid => unreachable,

            // flat copy
            .integer,
            .number,
            .enumeration,
            .margins,
            .color,
            .size,
            .point,
            .resource,
            .boolean,
            .object,
            .event,
            .name,
            => self,

            // require allocations:
            .size_list => |list| Self{ .size_list = try SizeList.init(allocator, list.items) },
            .object_list => |list| Self{ .object_list = try ObjectList.init(allocator, list.items) },
            .string => |string| Self{ .string = try String.init(allocator, string.items) },
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .invalid => unreachable,

            .integer,
            .number,
            .enumeration,
            .margins,
            .color,
            .size,
            .point,
            .resource,
            .boolean,
            .object,
            .event,
            .name,
            => {},

            .size_list => |*list| list.deinit(),
            .object_list => |*list| list.deinit(),
            .string => |*string| string.deinit(),
        }
        self.* = undefined;
    }

    pub fn from(value: anytype) Self {
        const t = comptime ZigToDunstblickType(@TypeOf(value));
        if (t == .enumeration)
            return Self{ .enumeration = @enumToInt(value) };
        return @unionInit(Self, @tagName(t), value);
    }

    pub fn to(self: Self, comptime T: type) !T {
        const dbt = comptime ZigToDunstblickType(T);

        if (self != dbt)
            return error.TypeMismatch;

        return @field(self, @tagName(dbt));
    }
};

/// Runs the test portion that is the same for all types of values)
fn genericValueTest(value: Value) !void {
    var dupe = try value.dupe(std.testing.allocator);
    defer dupe.deinit();

    std.testing.expectEqual(@as(Type, value), @as(Type, dupe));

    std.testing.expect(value.eql(dupe));
    std.testing.expect(dupe.eql(value));
}

test "Value (integer)" {
    var value = Value.from(@as(i32, 10));
    defer value.deinit();

    std.testing.expectEqual(Type.integer, @as(Type, value));
    std.testing.expectEqual(@as(i32, 10), value.integer);

    try genericValueTest(value);
}

test "Value (number)" {
    var value = Value.from(@as(f32, 3.1));
    defer value.deinit();

    std.testing.expectEqual(Type.number, @as(Type, value));
    std.testing.expectEqual(@as(f32, 3.1), value.number);

    try genericValueTest(value);
}

test "Value (string)" {
    var value = Value.from(try String.init(std.testing.allocator, "Hello, World!"));
    defer value.deinit();

    std.testing.expectEqual(Type.string, @as(Type, value));
    std.testing.expectEqualStrings("Hello, World!", value.string.items);

    try genericValueTest(value);
}

test "Value (enumeration)" {
    var value = Value.from(HAlignment.left);
    defer value.deinit();

    std.testing.expectEqual(Type.enumeration, @as(Type, value));
    std.testing.expectEqual(@enumToInt(Enumeration.left), value.enumeration);

    try genericValueTest(value);
}

test "Value (margins)" {
    var value = Value.from(Margin{ .left = 1, .right = 2, .top = 3, .bottom = 4 });
    defer value.deinit();

    std.testing.expectEqual(Type.margins, @as(Type, value));
    std.testing.expectEqual(Margin{ .left = 1, .right = 2, .top = 3, .bottom = 4 }, value.margins);

    try genericValueTest(value);
}

test "Value (color)" {
    var value = Value.from(Color{ .r = 1, .g = 2, .b = 3, .a = 4 });
    defer value.deinit();

    std.testing.expectEqual(Type.color, @as(Type, value));
    std.testing.expectEqual(Color{ .r = 1, .g = 2, .b = 3, .a = 4 }, value.color);

    try genericValueTest(value);
}

test "Value (size)" {
    var value = Value.from(Size{ .width = 1, .height = 2 });
    defer value.deinit();

    std.testing.expectEqual(Type.size, @as(Type, value));
    std.testing.expectEqual(Size{ .width = 1, .height = 2 }, value.size);

    try genericValueTest(value);
}

test "Value (point)" {
    var value = Value.from(Point{ .x = 1, .y = 2 });
    defer value.deinit();

    std.testing.expectEqual(Type.point, @as(Type, value));
    std.testing.expectEqual(Point{ .x = 1, .y = 2 }, value.point);

    try genericValueTest(value);
}

test "Value (resource)" {
    var value = Value.from(@intToEnum(ResourceId, 42));
    defer value.deinit();

    std.testing.expectEqual(Type.resource, @as(Type, value));
    std.testing.expectEqual(@intToEnum(ResourceId, 42), value.resource);

    try genericValueTest(value);
}

test "Value (boolean)" {
    var value = Value.from(true);
    defer value.deinit();

    std.testing.expectEqual(Type.boolean, @as(Type, value));
    std.testing.expectEqual(true, value.boolean);

    try genericValueTest(value);
}

test "Value (size_list)" {
    var value = Value.from(try SizeList.init(std.testing.allocator, &[_]SizeDef{ .auto, .expand }));
    defer value.deinit();

    std.testing.expectEqual(Type.size_list, @as(Type, value));
    std.testing.expectEqualSlices(SizeDef, &[_]SizeDef{ .auto, .expand }, value.size_list.items);

    try genericValueTest(value);
}

test "Value (object)" {
    var value = Value.from(@intToEnum(ObjectId, 42));
    defer value.deinit();

    std.testing.expectEqual(Type.object, @as(Type, value));
    std.testing.expectEqual(@intToEnum(ObjectId, 42), value.object);

    try genericValueTest(value);
}

test "Value (object_list)" {
    var value = Value.from(try ObjectList.init(std.testing.allocator, &[_]ObjectId{@intToEnum(ObjectId, 10)}));
    defer value.deinit();

    std.testing.expectEqual(Type.object_list, @as(Type, value));
    std.testing.expectEqualSlices(ObjectId, &[_]ObjectId{@intToEnum(ObjectId, 10)}, value.object_list.items);

    try genericValueTest(value);
}

test "Value (event)" {
    var value = Value.from(@intToEnum(EventId, 42));
    defer value.deinit();

    std.testing.expectEqual(Type.event, @as(Type, value));
    std.testing.expectEqual(@intToEnum(EventId, 42), value.event);

    try genericValueTest(value);
}

test "Value (name)" {
    var value = Value.from(@intToEnum(WidgetId, 42));
    defer value.deinit();

    std.testing.expectEqual(Type.name, @as(Type, value));
    std.testing.expectEqual(@intToEnum(WidgetId, 42), value.name);

    try genericValueTest(value);
}

fn ZigToDunstblickType(comptime T: type) Type {
    const ti = @typeInfo(T);
    if (ti == .Enum and ti.Enum.tag_type == u8) {
        return .enumeration;
    }
    return switch (T) {
        i32 => Type.integer,
        f32 => Type.number,
        String => Type.string,
        Margin => Type.margins,
        Color => Type.color,
        Size => Type.size,
        Point => Type.point,
        ResourceId => Type.resource,
        bool => Type.boolean,
        SizeList => Type.size_list,
        ObjectId => Type.object,
        ObjectList => Type.object_list,
        EventId => Type.event,
        WidgetId => Type.name,

        else => @compileError(@typeName(T) ++ " is not a supported dunstblick type!"),
    };
}

pub const SizeDef = union(enum) {
    const Self = @This();
    const Tag = std.meta.Tag(Self);

    auto,
    expand,
    pixels: u32,
    percent: f32,

    pub fn eql(self: Self, other: Self) bool {
        if (@as(Tag, self) != @as(Tag, other))
            return false;
        return switch (self) {
            .auto => true,
            .expand => true,
            .pixels => |p| (p == other.pixels),
            .percent => |p| std.math.approxEqAbs(f32, p, other.percent, 0.0001), // 0.1‰ precision for percentages
        };
    }
};

pub const WidgetType = enum(u8) {
    button = 1,
    label = 2,
    combobox = 3,
    treeview = 5,
    listbox = 7,
    picture = 9,
    textbox = 10,
    checkbox = 11,
    radiobutton = 12,
    scrollview = 13,
    scrollbar = 14,
    slider = 15,
    progressbar = 16,
    spinedit = 17,
    separator = 18,
    spacer = 19,
    panel = 20,
    container = 21,
    tab_layout = 250,
    canvas_layout = 251,
    flow_layout = 252,
    grid_layout = 253,
    dock_layout = 254,
    stack_layout = 255,
};

pub const Property = enum(u8) {
    const Self = @This();

    horizontal_alignment = 1,
    vertical_alignment = 2,
    margins = 3,
    paddings = 4,
    dock_site = 6,
    visibility = 7,
    size_hint = 8,
    font_family = 9,
    text = 10,
    minimum = 11,
    maximum = 12,
    value = 13,
    display_progress_style = 14,
    is_checked = 15,
    tab_title = 16,
    selected_index = 17,
    columns = 18,
    rows = 19,
    left = 20,
    top = 21,
    enabled = 22,
    image_scaling = 23,
    image = 24,
    binding_context = 25,
    child_source = 26,
    child_template = 27,
    hit_test_visible = 29,
    on_click = 30,
    orientation = 31,
    name = 32,

    comptime {
        for (@typeInfo(Widget.Properties).Struct.fields) |fld| {
            _ = @field(Self, fld.name);
        }
    }
};

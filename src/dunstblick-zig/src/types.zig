const std = @import("std");

pub const WidgetType = enum(u8) {
    // invalid = 0, // marks "end of children" in the binary format
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
    tab_layout = 250,
    canvas_layout = 251,
    flow_layout = 252,
    grid_layout = 253,
    dock_layout = 254,
    stack_layout = 255,
};

pub const Type = enum(u8) {
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
    sizelist = 11,
    object = 12,
    objectlist = 13,
    callback = 14,

    pub fn from(comptime T: type) Type {
        if (@typeInfo(T) == .Enum)
            return .enumeration;
        return switch (T) {
            i32 => .integer,
            f32 => .number,
            []const u8 => .string,
            Margins => .margins,
            Color => .color,
            Size => .size,
            Point => .point,
            ResourceID => .resource,
            bool => .boolean,
            SizeList => .sizelist,
            ObjectID => .object,
            ObjectList => .objectlist,
            CallbackID => .callback,
            else => @compileError("Type " ++ @typeName(T) ++ " is not convertible"),
        };
    }
};

/// This namespace contains the primitive enumeration values for all enumerations.
const Enumeration = struct {
    pub const none = 0;
    pub const left = 1;
    pub const center = 2;
    pub const right = 3;
    pub const top = 4;
    pub const middle = 5;
    pub const bottom = 6;
    pub const stretch = 7;
    pub const expand = 8;
    pub const auto = 9;
    pub const yesno = 10;
    pub const truefalse = 11;
    pub const onoff = 12;
    pub const visible = 13;
    pub const hidden = 14;
    pub const collapsed = 15;
    pub const vertical = 16;
    pub const horizontal = 17;
    pub const sans = 18;
    pub const serif = 19;
    pub const monospace = 20;
    pub const percent = 21;
    pub const absolute = 22;
    pub const zoom = 23;
    pub const contain = 24;
    pub const cover = 25;
};

pub const PropertyName = enum(u8) {
    horizontalAlignment = 1,
    verticalAlignment = 2,
    margins = 3,
    paddings = 4,
    dockSite = 6,
    visibility = 7,
    sizeHint = 8,
    fontFamily = 9,
    text = 10,
    minimum = 11,
    maximum = 12,
    value = 13,
    displayProgressStyle = 14,
    isChecked = 15,
    tabTitle = 16,
    selectedIndex = 17,
    columns = 18,
    rows = 19,
    left = 20,
    top = 21,
    enabled = 22,
    imageScaling = 23,
    image = 24,
    bindingContext = 25,
    childSource = 26,
    childTemplate = 27,
    hitTestVisible = 29,
    onClick = 30,
    orientation = 31,
};

fn UniqueID(comptime T: type) type {
    return struct {
        const This = @This();

        value: u32,

        pub fn init(val: u32) This {
            return This{ .value = val };
        }

        pub fn eql(a: This, b: This) bool {
            return a.value == b.value;
        }
    };
}

pub const ResourceID = UniqueID(@OpaqueType());
pub const CallbackID = UniqueID(@OpaqueType());
pub const PropertyID = UniqueID(@OpaqueType());

pub const Margins = struct {
    pub const zero: Margins = initAll(0);

    left: usize,
    top: usize,
    bottom: usize,
    right: usize,

    pub fn initAll(val: usize) Margins {
        return .{
            .left = val,
            .right = val,
            .top = val,
            .bottom = val,
        };
    }

    pub fn totalHorizontal(m: Margins) usize {
        return m.left + m.right;
    }

    pub fn totalVertical(m: Margins) usize {
        return m.top + m.bottom;
    }
};

pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
};

pub const Size = struct {
    width: usize,
    height: usize,
};

pub const Point = struct {
    x: isize,
    y: isize,
};

pub const Rectangle = struct {
    x: isize,
    y: isize,
    width: usize,
    height: usize,
};

pub const TableSizeDefition = union(enum) {
    auto: void,
    expand: void,
    pixel: usize,
    percent: f32,
};

pub const ObjectID = struct {
    const This = @This();

    const ObjectSpace = @import("object.zig");

    value: u32,

    pub fn init(val: u32) This {
        return This{ .value = val };
    }

    pub fn eql(a: This, b: This) bool {
        return a.value == b.value;
    }

    pub fn resolve(ref: This, store: ObjectSpace.ObjectStore) ?*ObjectSpace.Object {
        return store.get(ref);
    }
};

pub const SizeList = std.ArrayList(Size);
pub const ObjectList = std.ArrayList(ObjectID);

pub const Value = union(Type) {
    integer: i32,
    number: f32,
    string: []const u8,
    enumeration: u8,
    margins: Margins,
    color: Color,
    size: Size,
    point: Point,
    resource: ResourceID,
    boolean: bool,
    sizelist: SizeList,
    object: ObjectID,
    objectlist: ObjectList,
    callback: CallbackID,

    pub fn convertTo(value: Value, target: Type) !Value {
        if (@as(Type, value) == target)
            return value;
        return error.NotSupportedYet;
    }

    pub fn get(value: Value, comptime T: type) T {
        if (@typeInfo(T) == .Enum)
            return @intToEnum(T, value.enumeration);
        return switch (T) {
            i32 => value.integer,
            f32 => value.number,
            []const u8 => value.string,
            Margins => value.margins,
            Color => value.color,
            Size => value.size,
            Point => value.point,
            ResourceID => value.resource,
            bool => value.boolean,
            SizeList => value.sizelist,
            ObjectID => value.object,
            ObjectList => value.objectlist,
            CallbackID => value.callback,
            else => @compileError("Type " ++ @typeName(T) ++ " is not convertible"),
        };
    }

    pub fn initFrom(value: anytype) Value {
        const T = @TypeOf(value);
        if (@typeInfo(T) == .Enum)
            return Value{ .enumeration = @enumToInt(value) };
        // @compileLog(@tagName(comptime Type.from(T)));
        // return @unionInit(Value, comptime @tagName(comptime Type.from(T)), value);

        return switch (T) {
            i32 => Value{ .integer = value },
            f32 => Value{ .number = value },
            []const u8 => Value{ .string = value },
            Margins => Value{ .margins = value },
            Color => Value{ .color = value },
            Size => Value{ .size = value },
            Point => Value{ .point = value },
            ResourceID => Value{ .resource = value },
            bool => Value{ .boolean = value },
            SizeList => Value{ .sizelist = value },
            ObjectID => Value{ .object = value },
            ObjectList => Value{ .objectlist = value },
            CallbackID => Value{ .callback = value },
            else => @compileError("Type " ++ @typeName(T) ++ " is not convertible"),
        };
    }

    pub fn deinit(value: Value) void {
        switch (value) {
            .sizelist => |l| l.deinit(),
            .objectlist => |l| l.deinit(),
            else => {}, // nop
        }
    }
};

pub const HAlignment = enum(u8) {
    left = Enumeration.left,
    center = Enumeration.center,
    right = Enumeration.right,
    stretch = Enumeration.stretch,
};

pub const VAlignment = enum(u8) {
    top = Enumeration.top,
    middle = Enumeration.middle,
    bottom = Enumeration.bottom,
    stretch = Enumeration.stretch,
};

pub const DockSite = enum(u8) {
    top = Enumeration.top,
    left = Enumeration.left,
    right = Enumeration.right,
    bottom = Enumeration.bottom,
};

pub const Visibility = enum(u8) {
    visible = Enumeration.visible,
    hidden = Enumeration.hidden,
    collapsed = Enumeration.collapsed,
};

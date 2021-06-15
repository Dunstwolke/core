const std = @import("std");

pub const ResourceID = extern enum(u32) { invalid, _ };
pub const ObjectID = extern enum(u32) { invalid, _ };
pub const PropertyName = extern enum(u32) { invalid, _ };
pub const EventID = extern enum(u32) { invalid, _ };
pub const WidgetName = extern enum(u32) { none, _ };

pub const ResourceHash = [8]u8;

pub const ResourceKind = enum(u8) {
    /// A dunstblick layout.
    /// TODO: Write documentation
    layout = 0,

    /// A PNG bitmap
    /// See: https://en.wikipedia.org/wiki/Portable_Network_Graphics
    bitmap = 1,

    /// A TVG vector graphic.
    /// See: https://github.com/MasterQ32/tvg
    drawing = 2,
    _,
};

pub const Type = enum(u32) {
    // none = 0,
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
    event = 14,
    name = 15,
};

/// Possible properties a client can expose.
pub const ClientCapabilities = enum(u32) {
    /// The client does not have any capabilities. Provide the bare minimum GUI.
    none = 0,
    /// The client has a mouse with at least one button available.
    mouse = 1,
    /// The client has a keyboard available.
    keyboard = 2,
    /// The client has a touchscreen available.
    touch = 4,
    /// The client has a high-density screen. You might want to send larger bitmaps for
    /// improved display.
    highdpi = 8,
    /// The client screen allows to tilt the screen from landscape to portrait and back.
    /// You may provide a layout that can serve both.
    tiltable = 16,
    /// The client screen allows to be resized. You may provide a layout that can respect this.
    resizable = 32,
    /// The client requests to be screen-reader compatible. Serve simpler layouts when possible.
    req_accessibility = 64,
    _,
};

pub const DisconnectReason = enum(u32) {
    /// The user closed the connection.
    quit = 0,

    /// The connection was closed by a call to `Connection.close`.
    shutdown = 1,

    /// The display client did not respond for a longer time.
    timeout = 2,

    /// The network connection failed.
    network_error = 3,

    /// The client was forcefully disconnected for sending invalid data.
    invalid_data = 4,

    /// The protocol used by the display client is not compatible to this library.
    protocol_mismatch = 5,
    _,
};

pub const Color = extern struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
};

pub const Point = extern struct {
    x: i32,
    y: i32,
};

pub const Size = extern struct {
    width: u32,
    height: u32,

    pub fn addMargin(self: Size, margins: Margins) Size {
        return Size{
            .width = self.width + margins.totalHorizontal(),
            .height = self.height + margins.totalVertical(),
        };
    }
};

pub const Margins = extern struct {
    left: u32,
    top: u32,
    right: u32,
    bottom: u32,

    pub fn horizontalVertical(h: u32, v: u32) Margins {
        return Margins{
            .left = h,
            .top = v,
            .right = h,
            .bottom = v,
        };
    }

    pub fn all(v: u32) Margins {
        return Margins{
            .left = v,
            .top = v,
            .right = v,
            .bottom = v,
        };
    }

    pub fn totalHorizontal(self: Margins) u32 {
        return self.left + self.right;
    }

    pub fn totalVertical(self: Margins) u32 {
        return self.top + self.bottom;
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

pub const Property = enum(u7) {
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
    widget_name = 32,
};

pub const Enum = enum(u8) {
    none = 0,
    left = 1,
    center = 2,
    right = 3,
    top = 4,
    middle = 5,
    bottom = 6,
    stretch = 7,
    expand = 8,
    auto = 9,
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

// bitmask containing two bits per entry:
pub const ColumnSizeType = enum(u2) {
    /// the column/row will take the minimal space possible.
    auto = 0b00,
    /// the column/row will take all available space
    expand = 0b01,
    /// the column/row is specified as N pixels
    absolute = 0b10,
    /// the column/row is specified as a value between 0% and 100%.
    percentage = 0b11,
};

pub const ColumnSizeDefinition = union(ColumnSizeType) {
    auto,
    expand,
    absolute: u15,
    percentage: f32,
};

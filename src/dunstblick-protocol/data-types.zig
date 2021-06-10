const std = @import("std");

pub const ResourceID = extern enum(u32) { invalid, _ };
pub const ObjectID = extern enum(u32) { invalid, _ };
pub const PropertyName = extern enum(u32) { invalid, _ };
pub const EventID = extern enum(u32) { invalid, _ };
pub const WidgetName = extern enum(u32) { none, _ };

pub const ResourceHash = [8]u8;

pub const ResourceKind = extern enum(u8) {
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

pub const Type = extern enum(u32) {
    none = 0,
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
    object = 12,
    objectlist = 13,
    event = 14,
    name = 15,
    _,
};

/// Possible properties a client can expose.
pub const ClientCapabilities = extern enum(u32) {
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

pub const DisconnectReason = extern enum(u32) {
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
};

pub const Margins = extern struct {
    left: u32,
    top: u32,
    right: u32,
    bottom: u32,
};

// only required for the API
pub const ValueStorage = extern union {
    integer: i32,
    enumeration: u8,
    number: f32,
    string: [*:0]const u8,
    resource: ResourceID,
    object: ObjectID,
    color: Color,
    size: Size,
    point: Point,
    margins: Margins,
    boolean: bool,
    event: EventID,
    name: WidgetName,
};

pub const Value = extern struct {
    type: Type,
    value: ValueStorage,

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}(", .{@tagName(self.type)});
        switch (self.type) {
            .integer => try writer.print("{d}", .{self.value.integer}),
            .enumeration => try writer.print("{d}", .{self.value.enumeration}),
            .number => try writer.print("{d}", .{self.value.number}),
            .string => try writer.writeAll(std.mem.span(self.value.string)),
            .resource => try writer.print("{}", .{@enumToInt(self.value.resource)}),
            .object => try writer.print("{}", .{@enumToInt(self.value.object)}),
            .color => try writer.print("{},{},{},{}", .{
                self.value.color.red,
                self.value.color.green,
                self.value.color.blue,
                self.value.color.alpha,
            }),
            .size => try writer.print("{}x{}", .{
                self.value.size.width,
                self.value.size.height,
            }),
            .point => try writer.print("{},{}", .{
                self.value.point.x,
                self.value.point.y,
            }),
            .margins => try writer.print("{},{},{},{}", .{
                self.value.margins.left,
                self.value.margins.top,
                self.value.margins.right,
                self.value.margins.bottom,
            }),
            .boolean => try writer.print("{}", .{self.value.boolean}),
            .event => try writer.print("{}", .{@enumToInt(self.value.event)}),
            .name => try writer.print("{}", .{@enumToInt(self.value.name)}),

            else => try writer.writeAll("???"),
        }
        try writer.writeAll(")");
    }
};

// Required for C api
// pub const Provider = @Type(.Opaque);
// pub const Connection = @Type(.Opaque);
// pub const Object = @Type(.Opaque);

// this is only necessary for the C binding
// pub const Error = extern enum(c_int) {
//     none = 0,
//     invalid_arg = 1,
//     network = 2,
//     invalid_type = 3,
//     argument_out_of_range = 4,
//     out_of_memory = 5,
//     resource_not_found = 6,
//     _,
// };

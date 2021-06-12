const types = @import("data-types.zig");

fn val(e: types.Enum) u8 {
    return @enumToInt(e);
}

pub fn enumCast(src: types.Enum, comptime E: type) !E {
    return try std.math.intToEnum(val(src));
}

pub const HorizontalAlignment = enum(u8) {
    left = val(.left),
    center = val(.center),
    right = val(.right),
    stretch = val(.stretch),
};

pub const VerticalAlignment = enum(u8) {
    top = val(.top),
    center = val(.center),
    bottom = val(.bottom),
    stretch = val(.stretch),
};

pub const DockSite = enum(u8) {
    left = val(.left),
    right = val(.right),
    top = val(.top),
    bottom = val(.bottom),
};

pub const Visibility = enum(u8) {
    visible = val(.visible),
    hidden = val(.hidden),
    collapsed = val(.collapsed),
};

const Self = @This();

width: usize,
height: usize,

/// scanline distance in pixels
stride: usize,

pixels: [*]align(4) Color,

pub fn scanline(self: Self, y: usize) []align(4) Color {
    return self.pixels[self.stride * y .. self.stride * (y + 1)];
}

pub const Color = extern struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 0xFF,

    pub fn rgb(comptime str: *const [6]u8) Color {
        const std = @import("std");
        return Color{
            .r = std.fmt.parseInt(u8, str[0..2], 16) catch unreachable,
            .g = std.fmt.parseInt(u8, str[2..4], 16) catch unreachable,
            .b = std.fmt.parseInt(u8, str[4..6], 16) catch unreachable,
        };
    }
};

const std = @import("std");

const Self = @This();

width: usize,
height: usize,

/// scanline distance in pixels
stride: usize,

pixels: [*]align(4) Color,

pub fn scanline(self: Self, y: usize) []align(4) Color {
    return self.pixels[self.stride * y .. self.stride * (y + 1)];
}

pub fn view(self: Self, x: usize, y: usize, width: usize, height: usize) Self {
    return Self{
        .width = width,
        .height = height,
        .stride = self.stride,
        .pixels = self.pixels + (self.stride * y) + x,
    };
}

pub const Color = extern struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 0xFF,

    // Support for std.json:

    pub fn jsonStringify(value: @This(), options: std.json.StringifyOptions, writer: anytype) !void {
        try writer.print("\"#{X:0>2}{X:0>2}{X:0>2}", .{ value.r, value.g, value.b });
        if (value.a != 0xFF) {
            try writer.print("{X:0>2}", .{value.a});
        }
        try writer.writeAll("\"");
    }
};

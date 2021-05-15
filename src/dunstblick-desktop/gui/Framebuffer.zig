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

    pub fn alphaBlend(c0: Color, c1: Color, alpha: u8) Color {
        return alphaBlendF(c0, c1, @intToFloat(f32, alpha) / 255.0);
    }

    pub fn alphaBlendF(c0: Color, c1: Color, alpha: f32) Color {
        const f = std.math.clamp(alpha, 0.0, 1.0);
        return Color{
            .r = lerp(c0.r, c1.r, f),
            .g = lerp(c0.g, c1.g, f),
            .b = lerp(c0.b, c1.b, f),
            .a = lerp(c0.a, c1.a, f),
        };
    }

    fn lerp(a: u8, b: u8, f: f32) u8 {
        return @floatToInt(u8, @intToFloat(f32, a) + f * (@intToFloat(f32, b) - @intToFloat(f32, a)));
    }
};

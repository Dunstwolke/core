const std = @import("std");

const Self = @This();

width: usize,
height: usize,

/// distance between two scanlines in pixel count. Might be bigger than width.
stride: usize,

pixels: [*]align(4) Color,

pub fn scanline(self: Self, y: usize) []align(4) Color {
    return self.pixels[self.stride * y .. self.stride * (y + 1)];
}

pub fn view(self: Self) View {
    return View{
        .framebuffer = self,
        .offset_x = 0,
        .offset_y = 0,
        .width = self.width,
        .height = self.height,
    };
}

pub fn subView(self: Self, x: i16, y: i16, width: u15, height: u15) View {
    return View{
        .framebuffer = self,
        .offset_x = x,
        .offset_y = y,
        .width = width,
        .height = height,
    };
}

pub const View = struct {
    framebuffer: Self,
    offset_x: i16,
    offset_y: i16,
    width: u15,
    height: u15,

    pub fn pixel(self: View, x: i16, y: i16) ?*Color {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height)
            return null;
        if (self.offset_x + x < 0)
            return null;
        if (self.offset_y + y < 0)
            return null;

        const fb_x = @intCast(usize, self.offset_x + x);
        const fb_y = @intCast(usize, self.offset_y + y);
        if (fb_x >= self.framebuffer.width or fb_y >= self.framebuffer.height)
            return null;
        return &self.framebuffer.scanline(@intCast(usize, fb_y))[fb_x];
    }

    pub fn set(self: View, x: i16, y: i16, color: Color) void {
        if (self.pixel(x, y)) |px| {
            px.* = color;
        }
    }

    pub fn get(self: View, x: i16, y: i16) Color {
        return self.pixel(x, y) orelse Color.transparent;
    }
};

pub const Color = extern struct {
    pub const transparent = .{ .r = 0, .g = 0, .b = 0, .a = 0 };

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

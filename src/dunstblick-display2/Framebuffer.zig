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
};

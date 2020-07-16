const std = @import("std");

pub fn Canvas(
    comptime Framebuffer: type,
    comptime Pixel: type,
    comptime setPixelImpl: fn (Framebuffer, x: isize, y: isize, col: Pixel) void,
) type {
    return struct {
        const Self = @This();

        framebuffer: Framebuffer,

        pub fn init(fb: Framebuffer) Self {
            return Self{
                .framebuffer = fb,
            };
        }
    };
}

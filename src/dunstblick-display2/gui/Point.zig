const std = @import("std");

const Self = @This();

x: i16,
y: i16,

pub fn distance(a: Self, b: Self) u16 {
    return std.math.sqrt(distance2(a, b));
}

pub fn distance2(a: Self, b: Self) u32 {
    const dx = @as(u32, std.math.absCast(a.x - b.x));
    const dy = @as(u32, std.math.absCast(a.x - b.x));
    return dx * dx + dy * dy;
}

const Point = @import("Point.zig");
const Size = @import("Size.zig");

const Self = @This();

x: i16,
y: i16,
width: u15,
height: u15,

pub fn getPosition(self: Self) Point {
    return Point{ .x = self.x, .y = self.y };
}

pub fn getSize(self: Self) Size {
    return Size{ .width = self.width, .height = self.height };
}

pub fn contains(self: Self, pt: Point) bool {
    return (pt.x >= self.x) and
        (pt.y >= self.y) and
        (pt.x < self.x + self.width) and
        (pt.y < self.y + self.height);
}

pub fn init(position: Point, size: Size) Self {
    return Self{
        .x = position.x,
        .y = position.y,
        .width = size.width,
        .height = size.height,
    };
}

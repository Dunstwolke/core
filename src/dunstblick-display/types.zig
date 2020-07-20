pub const Point = extern struct {
    width: isize,
    height: isize,
};

pub const Size = extern struct {
    width: usize,
    height: usize,
};

pub const Rectangle = extern struct {
    const Self = @This();

    x: isize,
    y: isize,
    width: usize,
    height: usize,

    pub fn shrink(self: Self, amount: usize) Self {
        var result = self;
        result.x += @intCast(isize, amount);
        result.y += @intCast(isize, amount);
        result.width -= 2 * amount;
        result.height -= 2 * amount;
        return result;
    }

    pub fn grow(self: Self, amount: usize) Self {
        var result = self;
        result.x -= @intCast(isize, amount);
        result.y -= @intCast(isize, amount);
        result.width += 2 * amount;
        result.height += 2 * amount;
        return result;
    }

    pub fn contains(self: Self, x: isize, y: isize) bool {
        if (x < self.x or y < self.y)
            return false;
        if (x >= self.x + @intCast(isize, self.width) or y >= self.y + @intCast(isize, self.height))
            return false;
        return true;
    }

    pub fn isEmpty(self: Self) bool {
        return (self.width == 0) or (self.height == 0);
    }

    pub fn intersect(lhs: Self, rhs: Self) Self {
        const left = std.math.max(a.x, b.x);
        const top = std.math.max(a.y, b.y);

        const right = std.math.min(a.x + a.w, b.x + b.w);
        const bottom = std.math.min(a.y + a.h, b.y + b.h);

        return if (right < left or bottom < top)
            return Self{ .x = left, .y = top, .width = 0, .height = 0 }
        else
            return Self{ .x = left, .y = top, .width = right - left, .height = bottom - top };
    }
};

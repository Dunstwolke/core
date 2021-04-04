const std = @import("std");
const meta = @import("zig-meta");

// Design considerations:
// - Screen sizes are limited to 32k×32k (allows using i16 for coordinates)
// -

pub fn main() !void {}

const WindowTree = struct {
    const Layout = enum {
        /// Windows are stacked on top of each other.
        vertical,

        /// Windows are side-by-side next to each other
        horizontal,
    };

    const Window = struct {
        window: void,
    };

    const Group = struct {
        children: []Node,
    };

    const Node = union(enum) {
        window: Window,
        group: Group,
    };

    /// A relative screen rectangle. Base coordinates are [0,0,1,1]
    const Rectangle = struct {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
    };

    allocator: *std.mem.Allocator,
    root: Node,
};

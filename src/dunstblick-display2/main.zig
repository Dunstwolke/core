const std = @import("std");
const meta = @import("zig-meta");

const log = std.log.scoped(.application);

const Display = @import("Display.zig");

// Design considerations:
// - Screen sizes are limited to 32k×32k (allows using i16 for coordinates)
// -

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    log.debug("entering main loop...", .{});

    blk: while (display.alive) {
        while (try display.pollEvent()) |event| {
            switch (event) {
                .screen_resize => |ev| log.warn("unhandled event: screen_resize = {}", .{ev}),

                .mouse_down => |ev| log.warn("unhandled event: mouse_down = {}", .{ev}),
                .mouse_up => |ev| log.warn("unhandled event: mouse_up = {}", .{ev}),
                .mouse_motion => |ev| log.warn("unhandled event: mouse_motion = {}", .{ev}),

                .key_down => |ev| log.warn("unhandled event: key_down = {}", .{ev}),
                .key_up => |ev| log.warn("unhandled event: key_up = {}", .{ev}),
                .text_input => |ev| log.warn("unhandled event: text_input = {}", .{ev}),

                .quit => break :blk,
            }
        }

        var screen = try display.mapScreen();
        {
            var y: usize = 0;
            while (y < screen.height) : (y += 1) {
                var x: usize = 0;
                while (x < screen.width) : (x += 1) {
                    screen.pixels[@divExact(screen.stride, 4) * y + x] = Display.Color{
                        .r = @truncate(u8, x),
                        .g = @truncate(u8, y),
                        .b = @truncate(u8, x + y),
                    };
                }
            }
        }
        defer screen.unmap();
    }
}

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

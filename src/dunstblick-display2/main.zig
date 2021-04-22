const std = @import("std");
const meta = @import("zig-meta");

const log = std.log.scoped(.application);

const Display = @import("gui/Display.zig");
const HomeScreen = @import("gui/HomeScreen.zig");

// Design considerations:
// - Screen sizes are limited to 32k×32k (allows using i16 for coordinates)
// - Display api is platform independent

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    var display = try Display.init(allocator);
    defer display.deinit();

    log.debug("entering main loop...", .{});

    var homescreen = try HomeScreen.init(allocator, display.screen_size);
    defer homescreen.deinit();

    var frame_timer = try std.time.Timer.start();

    blk: while (display.alive) {
        while (try display.pollEvent()) |event| {
            switch (event) {
                .screen_resize => |size| {
                    try homescreen.resize(size);
                },

                .mouse_down => |ev| {
                    try homescreen.mouseDown(ev);
                },
                .mouse_up => |ev| {
                    try homescreen.mouseUp(ev);
                },
                .mouse_motion => |ev| {
                    homescreen.setMousePos(ev.position);
                },

                .key_down => |ev| log.warn("unhandled event: key_down = {}", .{ev}),
                .key_up => |ev| log.warn("unhandled event: key_up = {}", .{ev}),
                .text_input => |ev| log.warn("unhandled event: text_input = {}", .{ev}),

                .quit => break :blk,
            }
        }

        const frametime = @floatCast(f32, @intToFloat(f64, frame_timer.lap()) / std.time.ns_per_s);

        try homescreen.update(frametime);

        {
            var screen = try display.mapScreen();
            defer display.unmapScreen();

            {
                var y: usize = 0;
                while (y < screen.height) : (y += 1) {
                    var x: usize = 0;
                    while (x < screen.width) : (x += 1) {
                        screen.scanline(y)[x] = .{ .r = 0x00, .g = 0x40, .b = 0x40 };
                    }
                }
            }

            homescreen.render(screen);
        }
    }
}

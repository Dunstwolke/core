const std = @import("std");
const meta = @import("zig-meta");

const log = std.log.scoped(.application);

// Design considerations:
// - Screen sizes are limited to 32k×32k (allows using i16 for coordinates)
// - Display api is platform independent

const Size = @import("gui/Size.zig");
const Display = @import("gui/Display.zig");
const HomeScreen = @import("gui/HomeScreen.zig");
const Framebuffer = @import("gui/Framebuffer.zig");
const ApplicationDescription = @import("gui/ApplicationDescription.zig");
const ApplicationInstance = @import("gui/ApplicationInstance.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    var demo_app = DemoAppDescription{};

    var display = try Display.init(allocator);
    defer display.deinit();

    log.debug("entering main loop...", .{});

    var homescreen = try HomeScreen.init(allocator, display.screen_size);
    defer homescreen.deinit();

    try homescreen.setAvailableApps(&[_]*ApplicationDescription{&demo_app.desc});

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

const DemoAppDescription = struct {
    desc: ApplicationDescription = .{
        .display_name = "Dummy App",
        .icon = null, // testing the default icon fallback
        .vtable = ApplicationDescription.Interface.get(@This()),
    },

    pub fn spawn(desc: *ApplicationDescription, allocator: *std.mem.Allocator) !*ApplicationInstance {
        const app = try allocator.create(DemoApp);
        app.* = DemoApp{
            .allocator = allocator,
            .instance = ApplicationInstance{
                .description = desc.*,
                .vtable = ApplicationInstance.Interface.get(DemoApp),
            },
            .timer = std.time.milliTimestamp(),
            .msg_buf = undefined,
        };
        app.updateStatus();
        return &app.instance;
    }
};

const DemoApp = struct {
    allocator: *std.mem.Allocator,
    instance: ApplicationInstance,
    timer: i64,
    msg_buf: [64]u8,
    render_time: f32 = 0.0,

    pub fn update(instance: *ApplicationInstance, dt: f32) !void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);
        self.render_time += dt;
        self.updateStatus();
    }

    pub fn resize(instance: *ApplicationInstance, size: Size) !void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);
        @panic("DemoApp.resize not implemented yet!");
    }

    pub fn render(instance: *ApplicationInstance, target: Framebuffer.View) !void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);

        var y: u15 = 0;
        while (y < target.height) : (y += 1) {
            var x: u15 = 0;
            while (x < target.width) : (x += 1) {
                const fx = @intToFloat(f32, x) / 100.0;
                const fy = @intToFloat(f32, y) / 100.0;

                const t = @sin(0.3 * self.render_time + fx + 1.3 * fy + -0.3) -
                    0.7 * @sin(0.6 * self.render_time - 0.4 * fx + 0.3 * fy + 0.5) +
                    0.6 * @sin(1.1 * self.render_time + 0.1 * fx - 0.2 * fy + 0.8) -
                    0.5 * @sin(1.9 * self.render_time - 0.3 * fx + 0.2 * fy + 1.4) +
                    0.3 * @sin(2.3 * self.render_time + 0.2 * fx - 0.1 * fy + 2.4);

                target.set(x, y, .{
                    // assume pi=3
                    .r = @floatToInt(u8, 128.0 + 127.0 * @sin(2.5 * t + 0.0)),
                    .g = @floatToInt(u8, 128.0 + 127.0 * @sin(2.5 * t + 1.0)),
                    .b = @floatToInt(u8, 128.0 + 127.0 * @sin(2.5 * t + 2.0)),
                });
            }
        }
    }

    pub fn deinit(instance: *ApplicationInstance) void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);

        self.allocator.destroy(self);
    }

    fn updateStatus(self: *DemoApp) void {
        const startup_time = 10 * std.time.ms_per_s;
        const shutdown_time = 10.0;

        if (self.render_time > shutdown_time) {
            self.instance.status = .{ .exited = "Timed exit" };
        } else {
            const time = std.time.milliTimestamp();

            if (time < self.timer + startup_time) {
                self.instance.status = .{
                    .starting = std.fmt.bufPrint(&self.msg_buf, "Start in {d:.1} seconds.", .{
                        @intToFloat(f32, startup_time - (time - self.timer)) / 1000.0,
                    }) catch unreachable,
                };
                self.render_time = 0.0;
            } else {
                self.instance.status = .running;
            }
        }
    }
};

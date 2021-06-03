const std = @import("std");
const meta = @import("zig-meta");

const logger = std.log.scoped(.application);

const zero_graphics = @import("zero-graphics");

const AppDiscovery = @import("network/AppDiscovery.zig");

const gl = zero_graphics.gles;

// Design considerations:
// - Screen sizes are limited to 32k×32k (allows using i16 for coordinates)
// - Display api is platform independent

const Size = zero_graphics.Size;
const HomeScreen = @import("gui/HomeScreen.zig");
const ApplicationDescription = @import("gui/ApplicationDescription.zig");
const ApplicationInstance = @import("gui/ApplicationInstance.zig");

pub usingnamespace zero_graphics.EntryPoint(.desktop_sdl2);

pub const Application = struct {
    allocator: *std.mem.Allocator,
    input: *zero_graphics.Input,

    frame_timer: std.time.Timer,
    home_screen: HomeScreen,

    demo_app_desc: DemoAppDescription,

    renderer: zero_graphics.Renderer2D,

    screen_size: Size,

    debug_font: *const zero_graphics.Renderer2D.Font,

    app_discovery: AppDiscovery,

    available_apps: std.ArrayList(*ApplicationDescription),

    pub fn init(app: *Application, allocator: *std.mem.Allocator, input: *zero_graphics.Input) !void {
        try gl.load({}, loadOpenGlFunction);

        var frame_timer = try std.time.Timer.start();

        app.* = .{
            .allocator = allocator,
            .input = input,
            .frame_timer = frame_timer,
            .demo_app_desc = DemoAppDescription{},
            .screen_size = Size{ .width = 0, .height = 0 },
            .renderer = undefined,
            .home_screen = undefined,
            .debug_font = undefined,
            .available_apps = std.ArrayList(*ApplicationDescription).init(allocator),
            .app_discovery = undefined,
        };
        errdefer app.available_apps.deinit();

        app.renderer = try zero_graphics.Renderer2D.init(allocator);
        errdefer app.renderer.deinit();

        app.debug_font = try app.renderer.createFont(@embedFile("gui/fonts/firasans-regular.ttf"), 24);

        app.home_screen = try HomeScreen.init(allocator, &app.renderer);
        errdefer app.home_screen.deinit();

        app.app_discovery = try AppDiscovery.init(allocator);
        errdefer app.app_discovery.deinit();
    }

    pub fn deinit(app: *Application) void {
        app.app_discovery.deinit();
        app.home_screen.deinit();
        app.available_apps.deinit();
        app.* = undefined;
    }

    pub fn resize(app: *Application, width: u15, height: u15) !void {
        logger.info("resized screen to {}×{}", .{ width, height });
        app.screen_size = Size{ .width = width, .height = height };
        try app.home_screen.resize(app.screen_size);
    }

    pub fn update(app: *Application) !bool {
        defer app.renderer.reset();

        while (app.input.pollEvent()) |event| {
            switch (event) {
                .quit => return false,
                .pointer_press => |button| try app.home_screen.mouseDown(button),
                .pointer_release => |button| try app.home_screen.mouseUp(button),
                .pointer_motion => |position| app.home_screen.setMousePos(position),
                else => logger.info("unhandled event: {}", .{event}),
            }
        }

        try app.app_discovery.update();

        {
            app.available_apps.shrinkRetainingCapacity(0);
            try app.available_apps.append(&app.demo_app_desc.desc);
            {
                var iter = app.app_discovery.iterator();
                while (iter.next()) |netapp| {
                    try app.available_apps.append(&netapp.description);
                }
            }

            try app.home_screen.setAvailableApps(app.available_apps.items);
        }

        const frametime = @floatCast(f32, @intToFloat(f64, app.frame_timer.lap()) / std.time.ns_per_s);

        try app.home_screen.update(frametime);

        {
            try app.home_screen.render();

            var buf: [64]u8 = undefined;
            try app.renderer.drawString(
                app.debug_font,
                try std.fmt.bufPrint(&buf, "{d} ms", .{1000.0 * frametime}),
                10,
                app.screen_size.height - app.debug_font.font_size - 10,
                zero_graphics.Color.red,
            );
        }

        // OpenGL rendering
        {
            gl.viewport(0, 0, app.screen_size.width, app.screen_size.height);

            gl.clearColor(0.3, 0.3, 0.3, 1.0);
            gl.clear(gl.COLOR_BUFFER_BIT);

            gl.frontFace(gl.CCW);
            gl.cullFace(gl.BACK);

            app.renderer.render(app.screen_size);
        }

        return true;
    }
};

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

    pub fn render(instance: *ApplicationInstance, rectangle: zero_graphics.Rectangle, painter: *zero_graphics.Renderer2D) !void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);

        const Color = zero_graphics.Color;
        try painter.fillRectangle(rectangle, Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0x10 });

        const t = self.render_time;
        var points: [3][2]f32 = undefined;

        for (points) |*pt, i| {
            const offset = @intToFloat(f32, i);
            const mirror = std.math.sin((1.0 + 0.2 * offset) * t + offset);

            pt[0] = mirror * std.math.sin((0.1 * offset) * 0.4 * t + offset);
            pt[1] = mirror * std.math.cos((0.1 * offset) * 0.4 * t + offset);
        }

        var real_pt: [3]zero_graphics.Point = undefined;
        for (real_pt) |*dst, i| {
            const src = points[i];
            dst.* = .{
                .x = rectangle.x + @floatToInt(i16, (0.5 + 0.5 * src[0]) * @intToFloat(f32, rectangle.width)),
                .y = rectangle.y + @floatToInt(i16, (0.5 + 0.5 * src[1]) * @intToFloat(f32, rectangle.height)),
            };
        }
        var prev = real_pt[real_pt.len - 1];
        for (real_pt) |pt| {
            try painter.drawLine(
                pt.x,
                pt.y,
                prev.x,
                prev.y,
                zero_graphics.Color{ .r = 0xFF, .g = 0x00, .b = 0x80 },
            );
            prev = pt;
        }

        // TODO: Reimplement this as a custom shader effect
        // var y: u15 = 0;
        // while (y < target.height) : (y += 1) {
        //     var x: u15 = 0;
        //     while (x < target.width) : (x += 1) {
        //         const fx = @intToFloat(f32, x) / 100.0;
        //         const fy = @intToFloat(f32, y) / 100.0;

        //         const t = @sin(0.3 * self.render_time + fx + 1.3 * fy + -0.3) -
        //             0.7 * @sin(0.6 * self.render_time - 0.4 * fx + 0.3 * fy + 0.5) +
        //             0.6 * @sin(1.1 * self.render_time + 0.1 * fx - 0.2 * fy + 0.8) -
        //             0.5 * @sin(1.9 * self.render_time - 0.3 * fx + 0.2 * fy + 1.4) +
        //             0.3 * @sin(2.3 * self.render_time + 0.2 * fx - 0.1 * fy + 2.4);

        //         target.set(x, y, .{
        //             // assume pi=3
        //             .r = @floatToInt(u8, 128.0 + 127.0 * @sin(2.5 * t + 0.0)),
        //             .g = @floatToInt(u8, 128.0 + 127.0 * @sin(2.5 * t + 1.0)),
        //             .b = @floatToInt(u8, 128.0 + 127.0 * @sin(2.5 * t + 2.0)),
        //         });
        //     }
        // }
    }

    pub fn deinit(instance: *ApplicationInstance) void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);

        self.allocator.destroy(self);
    }

    fn updateStatus(self: *DemoApp) void {
        const startup_time = 3 * std.time.ms_per_s;
        const shutdown_time = 15.0;

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

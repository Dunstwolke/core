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

pub const zerog_enable_window_mode = (std.builtin.mode == .Debug) and (std.builtin.cpu.arch == .x86_64);

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

        try app.home_screen.beginInput();
        while (app.input.pollEvent()) |event| {
            switch (event) {
                .quit => return false,
                .pointer_press => |button| try app.home_screen.mouseDown(button),
                .pointer_release => |button| try app.home_screen.mouseUp(button),
                .pointer_motion => |position| app.home_screen.setMousePos(position),
                else => logger.info("unhandled event: {}", .{event}),
            }
        }
        try app.home_screen.endInput();

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
                try std.fmt.bufPrint(&buf, "{d:.2} ms", .{1000.0 * frametime}),
                app.screen_size.width - 100,
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
        .state = .ready,
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
    exit_request: bool = false,
    afterglow: u32 = 0,
    delta_t: u32 = 5, // 0.05

    pub fn update(instance: *ApplicationInstance, dt: f32) !void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);
        self.render_time += dt;
        self.updateStatus();
    }

    pub fn resize(instance: *ApplicationInstance, size: Size) !void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);
        @panic("DemoApp.resize not implemented yet!");
    }

    pub fn processUserInterface(instance: *ApplicationInstance, rectangle: zero_graphics.Rectangle, builder: zero_graphics.UserInterface.Builder) zero_graphics.UserInterface.Builder.Error!void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);
        var buf: [64]u8 = undefined;

        const exit_button_rect = zero_graphics.Rectangle{ .x = rectangle.x + 10, .y = rectangle.y + 10, .width = 120, .height = 32 };
        var minus_button_rect = zero_graphics.Rectangle{ .x = rectangle.x + 10, .y = rectangle.y + 50, .width = 32, .height = 32 };
        var afterglow_cnt_rect = zero_graphics.Rectangle{ .x = rectangle.x + 10, .y = rectangle.y + 50, .width = 120, .height = 32 };
        var plus_button_rect = zero_graphics.Rectangle{ .x = rectangle.x + 98, .y = rectangle.y + 50, .width = 32, .height = 32 };

        const clicked_exit = try builder.button(exit_button_rect, "Exit", null, .{});
        if (clicked_exit) {
            self.exit_request = true;
        }

        if (try builder.button(minus_button_rect, "-", null, .{ .enabled = (self.afterglow > 0) })) {
            self.afterglow -= 1;
        }

        if (try builder.button(plus_button_rect, "+", null, .{ .enabled = (self.afterglow < 25) })) {
            self.afterglow += 1;
        }

        try builder.label(
            afterglow_cnt_rect,
            std.fmt.bufPrint(&buf, "{d}", .{self.afterglow}) catch unreachable,
            .{
                .horizontal_alignment = .center,
            },
        );

        minus_button_rect.y += 40;
        afterglow_cnt_rect.y += 40;
        plus_button_rect.y += 40;

        if (try builder.button(minus_button_rect, "-", null, .{ .enabled = (self.delta_t > 0) })) {
            self.delta_t -= 1;
        }

        if (try builder.button(plus_button_rect, "+", null, .{ .enabled = (self.delta_t < 1000) })) {
            self.delta_t += 1;
        }

        try builder.label(
            afterglow_cnt_rect,
            std.fmt.bufPrint(&buf, "{d:.2}", .{0.01 * @intToFloat(f32, self.delta_t)}) catch unreachable,
            .{
                .horizontal_alignment = .center,
            },
        );

        try builder.label(
            zero_graphics.Rectangle{ .x = rectangle.x + 10, .y = rectangle.y + rectangle.height - 40, .width = 120, .height = 32 },
            std.fmt.bufPrint(&buf, "{d:.3} s", .{self.render_time}) catch unreachable,
            .{},
        );
    }

    pub fn render(instance: *ApplicationInstance, rectangle: zero_graphics.Rectangle, painter: *zero_graphics.Renderer2D) zero_graphics.Renderer2D.DrawError!void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);

        const Color = zero_graphics.Color;
        try painter.fillRectangle(rectangle, Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0x10 });

        var round: usize = 0;
        while (round <= self.afterglow) : (round += 1) {
            const t = self.render_time - 0.01 * @intToFloat(f32, self.delta_t) * @intToFloat(f32, round);
            const a = @intCast(u8, 255 - 10 * round);

            const r = @floatToInt(u8, 255.0 * (0.5 + 0.5 * std.math.sin(0.3 * t + 0.3)));
            const g = @floatToInt(u8, 255.0 * (0.5 + 0.5 * std.math.sin(0.3 * t + 1.3)));
            const b = @floatToInt(u8, 255.0 * (0.5 + 0.5 * std.math.sin(0.3 * t + 2.3)));

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
                    zero_graphics.Color{ .r = r, .g = g, .b = b, .a = a },
                );
                prev = pt;
            }
        }
    }

    pub fn deinit(instance: *ApplicationInstance) void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);
        self.allocator.destroy(self);
    }

    pub fn close(instance: *ApplicationInstance) void {
        const self = @fieldParentPtr(DemoApp, "instance", instance);
        self.instance.status = .{ .exited = "Closed by desktop environment" };
        std.log.scoped(.demo_app).info("closed", .{});
    }

    fn updateStatus(self: *DemoApp) void {
        const startup_time = 3 * std.time.ms_per_s;
        const shutdown_time = 60.0;

        if (self.render_time > shutdown_time) {
            self.instance.status = .{ .exited = "Timed exit" };
        } else if (self.exit_request) {
            self.instance.status = .{ .exited = "User requested exit" };
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

const std = @import("std");
const builtin = @import("builtin");
const meta = @import("zig-meta");
const known_folders = @import("known-folders");

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

// thread_local is broken on android
pub const crypto_always_getrandom = (builtin.abi == .android);

pub const zerog_enable_window_mode = (builtin.mode == .Debug) and (builtin.cpu.arch == .x86_64);

pub const Application = @This();

allocator: *std.mem.Allocator,
arena: std.heap.ArenaAllocator,
input: *zero_graphics.Input,

frame_timer: std.time.Timer,
home_screen: HomeScreen,

demo_app_desc: DemoAppDescription,

resource_manager: zero_graphics.ResourceManager,
renderer: zero_graphics.Renderer2D,

screen_size: Size,
bounded_size: Size,
virtual_size: Size,

debug_font: *const zero_graphics.Renderer2D.Font,

app_discovery: AppDiscovery,

available_apps: std.ArrayList(*ApplicationDescription),

settings: Settings,
settings_editor: SettingsEditor,

dpi_scale: f32 = 1.0,

settings_root_path: ?[]const u8,

pub fn init(app: *Application, allocator: *std.mem.Allocator, input: *zero_graphics.Input) !void {
    var frame_timer = try std.time.Timer.start();

    app.* = .{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .input = input,
        .frame_timer = frame_timer,
        .demo_app_desc = DemoAppDescription{},
        .screen_size = Size{ .width = 0, .height = 0 },
        .bounded_size = Size{ .width = 0, .height = 0 },
        .virtual_size = Size{ .width = 0, .height = 0 },
        .renderer = undefined,
        .home_screen = undefined,
        .debug_font = undefined,
        .available_apps = std.ArrayList(*ApplicationDescription).init(allocator),
        .app_discovery = undefined,
        .settings = Settings{
            .ui = .{
                .scale = @as(f32, 1.0),
                .padding = .{
                    .left = 0,
                    .top = 0,
                    .right = 0,
                    .bottom = 0,
                },
            },
            .home_screen = .{
                .workspace_bar = .{
                    .location = .left,
                    .button_size = 50,
                    .margins = 8,
                },
            },
        },
        .settings_editor = .{
            .settings = &app.settings,
        },
        .settings_root_path = null,
        .resource_manager = undefined,
    };
    errdefer app.arena.deinit();
    errdefer app.available_apps.deinit();

    if (zero_graphics.backend != .android) {
        app.settings_root_path = if (try known_folders.getPath(&app.arena.allocator, .local_configuration)) |folder|
            try std.fs.path.join(&app.arena.allocator, &[_][]const u8{ folder, "dunstblick" })
        else
            null;
    } else {
        const android = @import("root").android;

        // Go deep into zero-graphics.AndroidApp:
        // we know we're embedded into the AndroidApp
        const android_app = @fieldParentPtr(@import("root").AndroidApp, "application", app);

        var jni = android.JNI.init(android_app.activity);
        defer jni.deinit();

        app.settings_root_path = try jni.getFilesDir(&app.arena.allocator);
    }

    logger.info("load settings...", .{});
    _ = try app.loadSettings();

    logger.info("init resource manager...", .{});
    app.resource_manager = zero_graphics.ResourceManager.init(app.allocator);
    errdefer app.resource_manager.deinit();

    logger.info("init 2d renderer...", .{});
    app.renderer = try app.resource_manager.createRenderer2D();
    errdefer app.renderer.deinit();

    logger.info("load resources...", .{});
    app.debug_font = try app.renderer.createFont(@embedFile("gui/fonts/firasans-regular.ttf"), 24);

    logger.info("init app discovery...", .{});
    app.app_discovery = try AppDiscovery.init(allocator);
    errdefer app.app_discovery.deinit();

    logger.info("init home screen...", .{});
    app.home_screen = try HomeScreen.init(allocator, &app.resource_manager, &app.renderer, &app.settings.home_screen);
    errdefer app.home_screen.deinit();

    logger.info("app ready!", .{});
}

pub fn deinit(app: *Application) void {
    app.home_screen.deinit();
    app.app_discovery.deinit();
    app.available_apps.deinit();
    app.renderer.deinit();
    app.resource_manager.deinit();
    app.* = undefined;
    logger.info("app dead", .{});
}

pub fn setupGraphics(app: *Application) !void {
    try app.resource_manager.initializeGpuData();

    try app.updateDpiScale();
}

pub fn teardownGraphics(app: *Application) void {
    app.resource_manager.destroyGpuData();
}

fn loadSettings(app: *Application) !bool {
    if (zero_graphics.backend == .android) {
        logger.emerg("Android file I/O doesn't work properly yet", .{});
        return false;
    }

    const settings_root_path = app.settings_root_path orelse {
        logger.warn("no configuration folder could be found!", .{});
        return false;
    };

    logger.info("load configuration from {s}", .{settings_root_path});

    if (std.fs.cwd().openDir(settings_root_path, .{})) |*dir| {
        defer dir.close();

        const data = dir.readFileAlloc(app.allocator, "settings.json", 1 << 20) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => |e| return e,
        };
        defer app.allocator.free(data);

        // we got the app source

        var stream = std.json.TokenStream.init(data);
        var new_settings = try std.json.parse(Settings, &stream, .{});

        // prevent RLS to do partial writes
        app.settings = new_settings;

        try app.updateDpiScale();

        return true;
    } else |err| {
        logger.err("could not open condig folder: {s}", .{@errorName(err)});
        return false;
    }
}

fn saveSettings(app: *Application) !bool {
    // if (zero_graphics.backend == .android) {
    //     logger.emerg("Android file I/O doesn't work properly yet", .{});
    //     return false;
    // }

    const settings_root_path = app.settings_root_path orelse {
        logger.warn("no configuration folder could be found!", .{});
        return false;
    };

    logger.info("save configuration to {s}", .{settings_root_path});

    if (std.fs.cwd().makeOpenPath(settings_root_path, .{})) |*dir| {
        defer dir.close();

        var atomic_file = try dir.atomicFile("settings.json", .{});

        try std.json.stringify(app.settings, .{
            .whitespace = .{
                .indent = .{ .Space = 2 },
            },
        }, atomic_file.file.writer());

        try atomic_file.finish();

        return true;
    } else |err| {
        logger.err("could not open condig folder: {s}", .{@errorName(err)});
        return false;
    }
}

pub fn resize(app: *Application, width: u15, height: u15) !void {
    const new_size = Size{ .width = width, .height = height };
    if (!std.meta.eql(app.screen_size, new_size)) {
        logger.info("resized screen to {}×{}", .{ width, height });
        app.screen_size = new_size;

        try app.updateDpiScale();
    }
}

fn getTotalScale(app: Application) f32 {
    // dpi_scale makes renderer work on 1/10mm units,
    // ui.scale will apply user scaling
    return app.dpi_scale * app.settings.ui.scale;
}

fn updateDpiScale(app: *Application) !void {
    const dpi = zero_graphics.getDisplayDPI();
    app.dpi_scale = dpi / 254;
    logger.info("Display DPI: {d:.3} (scale: {d})", .{ dpi, app.dpi_scale });

    if (!app.screen_size.isEmpty()) {

        // Compute the inner screen size
        app.bounded_size = Size{
            .width = app.screen_size.width - app.settings.ui.padding.left - app.settings.ui.padding.right,
            .height = app.screen_size.height - app.settings.ui.padding.top - app.settings.ui.padding.bottom,
        };

        app.renderer.unit_to_pixel_ratio = app.getTotalScale();

        app.virtual_size = app.renderer.getVirtualScreenSize(app.bounded_size);

        try app.home_screen.resize(app.virtual_size);
    } else {
        app.bounded_size = Size.empty;
        app.virtual_size = Size.empty;
    }
}

fn physToVirtual(app: Application, pt: zero_graphics.Point) zero_graphics.Point {
    return .{
        .x = @floatToInt(i16, @intToFloat(f32, pt.x - app.settings.ui.padding.left) / app.getTotalScale()),
        .y = @floatToInt(i16, @intToFloat(f32, pt.y - app.settings.ui.padding.top) / app.getTotalScale()),
    };
}

fn virtToPhysical(app: Application, pt: zero_graphics.Point) zero_graphics.Point {
    return .{
        .x = @floatToInt(i16, app.getTotalScale() * @intToFloat(f32, pt.x)) + app.settings.ui.padding.left,
        .y = @floatToInt(i16, app.getTotalScale() * @intToFloat(f32, pt.y)) + app.settings.ui.padding.top,
    };
}

pub fn update(app: *Application) !bool {
    defer app.renderer.reset();

    try app.home_screen.beginInput();
    while (app.input.pollEvent()) |event| {
        switch (event) {
            .quit => return false,
            .pointer_press => |button| try app.home_screen.mouseDown(button),
            .pointer_release => |button| try app.home_screen.mouseUp(button),
            .pointer_motion => |position| app.home_screen.setMousePos(app.physToVirtual(position)),
            else => logger.info("unhandled event: {}", .{event}),
        }
    }

    try app.home_screen.endInput();

    try app.app_discovery.update();

    {
        app.available_apps.shrinkRetainingCapacity(0);
        try app.available_apps.append(&app.settings_editor.description);
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

    if (!app.home_screen.size.isEmpty()) {
        try app.home_screen.update(frametime);
    }

    return true;
}

pub fn render(app: *Application) !void {
    {
        if (!app.home_screen.size.isEmpty()) {
            try app.home_screen.render();
        }

        // var buf: [64]u8 = undefined;
        // try app.renderer.drawString(
        //     app.debug_font,
        //     try std.fmt.bufPrint(&buf, "{d:.2} ms", .{1000.0 * frametime}),
        //     app.virtual_size.width - 100,
        //     app.virtual_size.height - app.debug_font.font_size - 10,
        //     zero_graphics.Color.red,
        // );

        // try app.renderer.?.fillRectangle(
        //     .{
        //         .x = 100,
        //         .y = 200,
        //         .width = 300,
        //         .height = 500,
        //     },
        //     zero_graphics.Color.red,
        // );
    }

    // OpenGL rendering
    {
        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.viewport(
            app.settings.ui.padding.left,
            app.settings.ui.padding.bottom,
            app.bounded_size.width,
            app.bounded_size.height,
        );

        gl.frontFace(gl.CCW);
        gl.cullFace(gl.BACK);

        app.renderer.render(app.bounded_size);
    }
}

const Settings = struct {
    ui: UserInterface,
    home_screen: HomeScreen.Config,

    const UserInterface = struct {
        scale: f32,
        padding: Padding,
    };

    const Padding = struct {
        left: u15,
        top: u15,
        right: u15,
        bottom: u15,
    };
};

const SettingsEditor = struct {
    const description = ApplicationDescription{
        .display_name = "Settings",
        .icon = @embedFile("gui/icons/settings.tvg"),
        .vtable = ApplicationDescription.Interface.get(@This()),
        .state = .ready,
    };
    description: ApplicationDescription = description,
    instance: ApplicationInstance = ApplicationInstance{
        .description = description,
        .vtable = ApplicationInstance.Interface.get(@This()),
        .status = .running,
    },

    settings: *Settings,

    pub fn spawn(desc: *ApplicationDescription, allocator: *std.mem.Allocator) ApplicationDescription.Interface.SpawnError!*ApplicationInstance {
        _ = allocator;

        const settings = @fieldParentPtr(@This(), "description", desc);
        settings.instance.status = .running;
        return &settings.instance;
    }

    pub fn destroy(desc: *ApplicationDescription) ApplicationDescription.Interface.DestroyError!void {
        _ = desc;
    }

    const UiBuilder = struct {
        ui: zero_graphics.UserInterface.Builder,
        stack: zero_graphics.UserInterface.VerticalStackLayout,

        pub fn header(self: *UiBuilder, title: []const u8) !void {
            const rect = self.stack.get(32);
            try self.ui.panel(rect, .{ .id = title.ptr });
            try self.ui.label(rect, title, .{ .horizontal_alignment = .center, .id = title.ptr });
        }

        pub fn shrinkHorizontal(self: *UiBuilder, spacing: u15) !void {
            self.stack.base_rectangle.x += spacing / 2;
            self.stack.base_rectangle.width -= spacing;
        }

        pub fn advance(self: *UiBuilder, spacing: u15) !void {
            self.stack.advance(spacing);
        }

        pub fn number(self: *UiBuilder, comptime T: type, value: *T, comptime fmt: []const u8, increment: T, min: ?T, max: ?T) !bool {
            var dock = zero_graphics.UserInterface.DockLayout.init(self.stack.get(32));

            var changed = false;

            if (try self.ui.button(dock.get(.right, 32).shrink(1), "+", null, .{
                .id = value,
                .enabled = if (max) |m| (value.* < m) else true,
            })) {
                if (max) |m| {
                    value.* = std.math.min(m, value.* + increment);
                } else {
                    value.* += increment;
                }
                changed = true;
            }

            if (try self.ui.button(dock.get(.right, 32).shrink(1), "-", null, .{
                .id = value,
                .enabled = if (min) |m| (value.* > m) else true,
            })) {
                if (min) |m| {
                    value.* = std.math.max(m, value.* - increment);
                } else {
                    value.* += increment;
                }
                changed = true;
            }

            var buf = std.mem.zeroes([64]u8);
            try self.ui.label(
                dock.getRest(),
                std.fmt.bufPrint(&buf, fmt, .{value.*}) catch unreachable,
                .{ .id = value },
            );

            return changed;
        }
    };

    pub fn processUserInterface(instance: *ApplicationInstance, rectangle: zero_graphics.Rectangle, ui: zero_graphics.UserInterface.Builder) ApplicationInstance.Interface.UiError!void {
        const self = @fieldParentPtr(@This(), "instance", instance);

        const app = @fieldParentPtr(Application, "settings_editor", self);

        const root_rect = rectangle.centered(std.math.min(300, rectangle.width), rectangle.height);

        var builder = UiBuilder{
            .stack = zero_graphics.UserInterface.VerticalStackLayout.init(root_rect),
            .ui = ui,
        };
        try builder.header("Settings");
        try builder.advance(16);
        try builder.shrinkHorizontal(20);

        if (try builder.number(f32, &self.settings.ui.scale, "DPI Scale: {d:.2}", 0.1, 0.1, null)) {
            try app.updateDpiScale();
        }

        try builder.advance(16);

        if (try builder.number(u15, &self.settings.ui.padding.left, "Padding left: {d}", 1, 0, null)) {
            try app.updateDpiScale();
        }
        if (try builder.number(u15, &self.settings.ui.padding.right, "Padding right: {d}", 1, 0, null)) {
            try app.updateDpiScale();
        }
        if (try builder.number(u15, &self.settings.ui.padding.top, "Padding top: {d}", 1, 0, null)) {
            try app.updateDpiScale();
        }
        if (try builder.number(u15, &self.settings.ui.padding.bottom, "Padding bottom: {d}", 1, 0, null)) {
            try app.updateDpiScale();
        }

        try builder.advance(16);

        {
            const location = &self.settings.home_screen.workspace_bar.location;

            var dock = zero_graphics.UserInterface.DockLayout.init(builder.stack.get(32));
            try ui.label(dock.get(.right, 80), "Bottom", .{ .horizontal_alignment = .right });
            if (try ui.radioButton(dock.get(.right, 32), (location.* == .bottom), .{})) {
                location.* = .bottom;
            }

            try ui.label(dock.getRest(), "Workspace Bar:", .{});

            dock = zero_graphics.UserInterface.DockLayout.init(builder.stack.get(32));
            try ui.label(dock.get(.right, 80), "Left", .{ .horizontal_alignment = .right });
            if (try ui.radioButton(dock.get(.right, 32), (location.* == .left), .{})) {
                location.* = .left;
            }

            dock = zero_graphics.UserInterface.DockLayout.init(builder.stack.get(32));
            try ui.label(dock.get(.right, 80), "Top", .{ .horizontal_alignment = .right });
            if (try ui.radioButton(dock.get(.right, 32), (location.* == .top), .{})) {
                location.* = .top;
            }

            dock = zero_graphics.UserInterface.DockLayout.init(builder.stack.get(32));
            try ui.label(dock.get(.right, 80), "Right", .{ .horizontal_alignment = .right });
            if (try ui.radioButton(dock.get(.right, 32), (location.* == .right), .{})) {
                location.* = .right;
            }
        }
        try builder.advance(16);
        {
            var dock = zero_graphics.UserInterface.DockLayout.init(builder.stack.get(32));

            if (try builder.ui.button(dock.get(.left, 100), "Cancel", null, .{})) {
                _ = app.loadSettings() catch return error.IoError;

                self.instance.status = .{ .exited = "" };
            }

            if (try builder.ui.button(dock.get(.right, 100), "Save", null, .{
                .enabled = (app.settings_root_path != null),
            })) {
                if (app.saveSettings() catch return error.IoError) {
                    self.instance.status = .{ .exited = "" };
                }
            }
        }
    }
    pub fn deinit(instance: *ApplicationInstance) void {
        _ = instance;
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

    // pub fn resize(instance: *ApplicationInstance, size: Size) !void {
    //     const self = @fieldParentPtr(DemoApp, "instance", instance);
    //     _ = self;
    //     @panic("DemoApp.resize not implemented yet!");
    // }

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

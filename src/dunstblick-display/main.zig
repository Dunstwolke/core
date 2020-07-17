const std = @import("std");
const args_parser = @import("args");
const sdl = @import("sdl2");
const uri = @import("uri");

const painting = @import("painting.zig");

usingnamespace @import("types.zig");

pub fn main() !u8 {
    var counter = std.testing.LeakCountAllocator.init(std.heap.c_allocator);
    defer {
        counter.validate() catch {};
    }

    const gpa = &counter.allocator;

    try painting.init(gpa);
    defer painting.deinit();

    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();

    var cli = try args_parser.parseForCurrentProcess(struct {
        help: bool = false,
        discovery: ?bool = null,

        pub const shorthands = .{
            .d = "discovery",
            .h = "help",
        };
    }, gpa);
    defer cli.deinit();

    if (cli.options.help) {
        try printUsage();
        return 0;
    }

    if (cli.options.discovery == null) {
        cli.options.discovery = (cli.positionals.len == 0);
    }

    if ((cli.options.discovery.? == false) and (cli.positionals.len == 0)) {
        try printUsage();
        return 1;
    }

    const stderr = std.io.getStdErr().writer();

    {
        var all_valid = false;
        for (cli.positionals) |pos| {
            const url = uri.parse(pos) catch {
                try stderr.print("{} is not a valid URL!\n", .{pos});
                all_valid = false;
                continue;
            };
            if (url.scheme == null) {
                try stderr.print("{} is missing the scheme!\n", .{pos});
                all_valid = false;
                continue;
            }
            if (url.host == null) {
                try stderr.print("{} is missing the host name!\n", .{pos});
                all_valid = false;
                continue;
            }
            if (url.port == null) {
                try stderr.print("{} is missing the port number!\n", .{pos});
                all_valid = false;
                continue;
            }
            if ((url.path orelse "").len != 0 and !std.mem.eql(u8, url.path.?, "/")) {
                try stderr.print("{} has a invalid path component!\n", .{pos});
                all_valid = false;
                continue;
            }
        }
    }

    var window_list = std.TailQueue(UiContext).init();

    if (cli.options.discovery.?) {
        var context = try UiContext.init("Dunstblick Services", 240, 400);
        errdefer context.deinit();

        const node = try gpa.create(UiNode);
        node.* = UiNode.init(context);

        window_list.append(node);
    }

    core_loop: while (window_list.len > 0) {
        while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :core_loop,
                .window => |win_ev| {
                    const win = sdl.Window.fromID(win_ev.window_id) orelse continue;

                    var it = window_list.first;
                    const ctx = while (it) |c| : (it = c.next) {
                        if (c.data.window.ptr == win.ptr)
                            break c;
                    } else continue;

                    switch (win_ev.type) {
                        .close => {
                            window_list.remove(ctx);
                            ctx.data.deinit();
                            gpa.destroy(ctx);
                        },
                        .resized => |size| {
                            try ctx.data.resize(size);
                            try ctx.data.render();
                        },
                        .size_changed => {},
                        else => std.log.debug(.app, "{} {}\n", .{ win, win_ev }),
                    }
                },
                else => std.log.warn(.app, "Unhandled event: {}\n", .{
                    @as(sdl.EventType, ev),
                }),
            }
        }

        var it = window_list.first;
        while (it) |ctx| : (it = ctx.next) {
            try ctx.data.render();
        }
    }

    if (window_list.len > 0) {
        std.log.info(.app, "Cleaning up {} unclosed windows...\n", .{
            window_list.len,
        });
        while (window_list.pop()) |node| {
            node.data.deinit();
            gpa.destroy(node);
        }
    }
    return 0;
}

fn printUsage() !void {
    const out = std.io.getStdErr().writer();

    try out.writeAll(
        \\dunstblick-display [--help] [--discovery] [app] [app] …
        \\Connects to one or more Dunstblick applications.
        \\Each application will get its own window.
        \\
        \\--help, -h       Prints this help text.
        \\--discovery, -d  Shows a separate discovery window that will search for
        \\                 available Dunstblick applications in your network.
        \\                 Allows you to connect to them with a UI. This is the
        \\                 default when no explicit server is passed.
        \\app              A Dunstblick uri that should be connected to.
        \\                 Each passed URI will be openend as a separate window.           
        \\
    );
}

const UiContext = struct {
    const Self = @This();

    window: sdl.Window,
    renderer: sdl.Renderer,
    back_buffer: sdl.Texture,
    screen_size: sdl.Size,

    const backbuffer_format = .abgr8888;

    fn init(title: [:0]const u8, width: u32, height: u32) !Self {
        var win = try sdl.createWindow(
            "Dunstblick Services",
            .{ .centered = {} },
            .{ .centered = {} },
            240,
            400,
            .{ .shown = true, .resizable = true },
        );
        errdefer win.destroy();

        var ren = try sdl.createRenderer(win, null, .{
            .present_vsync = true,
        });
        errdefer ren.destroy();

        var backbuffer = try sdl.createTexture(ren, backbuffer_format, .streaming, width, height);
        errdefer backbuffer.destroy();

        return Self{
            .window = win,
            .renderer = ren,
            .back_buffer = backbuffer,
            .screen_size = sdl.Size{
                .width = @intCast(c_int, width),
                .height = @intCast(c_int, height),
            },
        };
    }

    fn deinit(self: *Self) void {
        self.back_buffer.destroy();
        self.renderer.destroy();
        self.window.destroy();
        self.* = undefined;
    }

    fn resize(self: *Self, new_size: sdl.Size) !void {
        var new_back_buffer = try sdl.createTexture(
            self.renderer,
            backbuffer_format,
            .streaming,
            @intCast(usize, new_size.width),
            @intCast(usize, new_size.height),
        );
        errdefer new_back_buffer.destroy();

        self.back_buffer.destroy();

        self.back_buffer = new_back_buffer;
        self.screen_size = new_size;
    }

    fn render(self: *Self) !void {
        {
            var pixels = try self.back_buffer.lock(null);
            defer pixels.release();

            var fb = painting.Painter{
                .pixels = &pixels,
                .size = self.screen_size,
                .scheme = painting.ColorScheme{},
            };

            fb.fill(fb.scheme.background);

            fb.drawHLine(10, 10, 220, .edge);
            fb.drawHLine(10, 30, 220, .crease);

            fb.drawVLine(10, 40, 220, .edge);
            fb.drawVLine(230, 40, 220, .crease);

            // filled rectangles

            fb.fillRectangle(Rectangle{
                .x = 25,
                .y = 45,
                .width = 40,
                .height = 40,
            }, .highlight);

            fb.fillRectangle(Rectangle{
                .x = 75,
                .y = 45,
                .width = 40,
                .height = 40,
            }, .background);

            fb.fillRectangle(Rectangle{
                .x = 125,
                .y = 45,
                .width = 40,
                .height = 40,
            }, .input_field);

            fb.fillRectangle(Rectangle{
                .x = 175,
                .y = 45,
                .width = 40,
                .height = 40,
            }, .checkered);

            // rectangle outlines

            fb.drawRectangle(Rectangle{
                .x = 25,
                .y = 95,
                .width = 40,
                .height = 40,
            }, .edge);

            fb.drawRectangle(Rectangle{
                .x = 75,
                .y = 95,
                .width = 40,
                .height = 40,
            }, .crease);

            fb.drawRectangle(Rectangle{
                .x = 125,
                .y = 95,
                .width = 40,
                .height = 40,
            }, .raised);

            fb.drawRectangle(Rectangle{
                .x = 175,
                .y = 95,
                .width = 40,
                .height = 40,
            }, .sunken);

            fb.drawRectangle(Rectangle{
                .x = 25,
                .y = 145,
                .width = 40,
                .height = 40,
            }, .input_field);

            fb.drawRectangle(Rectangle{
                .x = 75,
                .y = 145,
                .width = 40,
                .height = 40,
            }, .button_default);

            fb.drawRectangle(Rectangle{
                .x = 125,
                .y = 145,
                .width = 40,
                .height = 40,
            }, .button_active);

            fb.drawRectangle(Rectangle{
                .x = 175,
                .y = 145,
                .width = 40,
                .height = 40,
            }, .button_pressed);

            fb.drawString("¡Hello, Wörld!", Rectangle{
                .x = 25,
                .y = 195,
                .width = 190,
                .height = 40,
            }, .sans, .left);

            fb.drawString("¡Hello, Wörld!", Rectangle{
                .x = 25,
                .y = 215,
                .width = 190,
                .height = 40,
            }, .serif, .right);

            fb.drawString("¡Hello, Wörld!", Rectangle{
                .x = 25,
                .y = 235,
                .width = 190,
                .height = 40,
            }, .monospace, .center);

            fb.drawString(
                \\Li Europan lingues es membres
                \\del sam familie. Lor separat
                \\existentie es un myth. Por
                \\scientie, musica, sport etc,
                \\litot Europa usa li sam vocabular.
                \\Li lingues differe solmen in li
            , Rectangle{
                .x = 10,
                .y = 260,
                .width = 220,
                .height = 80,
            }, .sans, .left);
        }

        try self.renderer.setColor(sdl.Color.white);
        try self.renderer.clear();
        try self.renderer.copy(self.back_buffer, null, null);
        self.renderer.present();
    }
};

const UiNode = std.TailQueue(UiContext).Node;

const std = @import("std");
const sdl = @import("sdl2");
const log = std.log.scoped(.app);

const cpp = @import("cpp.zig");
const painting = @import("painting.zig");

const Session = @import("session.zig").Session;

usingnamespace @import("types.zig");

pub const Window = struct {
    const Self = @This();

    window: sdl.Window,
    renderer: sdl.Renderer,
    back_buffer: sdl.Texture,
    screen_size: Size,
    session: ?*Session = null,

    alive: bool = true,

    const backbuffer_format = .abgr8888;

    pub fn init(title: [:0]const u8, width: u32, height: u32) !Self {
        var win = try sdl.createWindow(
            title,
            .{ .centered = {} },
            .{ .centered = {} },
            width,
            height,
            .{ .shown = true, .resizable = true, .utility = true },
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
            .screen_size = Size{
                .width = width,
                .height = height,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.session) |session| {
            session.destroy(session);
        }
        self.back_buffer.destroy();
        self.renderer.destroy();
        self.window.destroy();
        self.* = undefined;
    }

    pub fn resize(self: *Self, new_size: Size) !void {
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

    pub fn update(self: *Self) void {
        if (self.session) |session| {
            self.alive = session.update(session) catch |err| blk: {
                log.err("failed to update session: {}\n", .{err});
                break :blk false;
            };
        }
    }

    pub fn pushEvent(self: *Self, event: sdl.c.SDL_Event) void {
        if (self.session) |session| {
            cpp.session_pushEvent(session.cpp_session, &event);
        }
    }

    pub fn render(self: *Self) !void {
        {
            var pixels = try self.back_buffer.lock(null);
            defer pixels.release();

            var fb = painting.Painter{
                .pixels = &pixels,
                .size = self.screen_size,
                .scheme = painting.ColorScheme{},
            };

            fb.fill(fb.scheme.background);

            if (self.session) |session| {
                cpp.session_render(
                    session.cpp_session,
                    Rectangle{
                        .x = 0,
                        .y = 0,
                        .width = self.screen_size.width,
                        .height = self.screen_size.height,
                    },
                    &fb.api,
                );
            }
        }

        try self.renderer.setColor(sdl.Color.white);
        try self.renderer.clear();
        try self.renderer.copy(self.back_buffer, null, null);
        self.renderer.present();
    }
};

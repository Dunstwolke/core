const std = @import("std");
const sdl = @import("sdl2");
const build_options = @import("build_options");
const log = std.log.scoped(.display);

const Self = @This();

pub const requires_softmouse = switch (build_options.render_backend) {
    .sdl2 => false,
    .drm => true,
};

const Point = struct {
    x: i16,
    y: i16,
};

const Size = struct {
    width: u16,
    height: u16,
};

pub const Color = extern struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 0xFF,
};

allocator: *std.mem.Allocator,
alive: bool,
backend: Backend,

mouse_position: Point,

pub fn init(allocator: *std.mem.Allocator) !Self {
    return Self{
        .allocator = allocator,
        .alive = true,
        .backend = try Backend.init(allocator),
        .mouse_position = Point{ .x = 0, .y = 0 },
    };
}

pub fn deinit(self: *Self) void {
    self.backend.deinit();
    self.* = undefined;
}

pub const MouseButton = enum {
    left,
    right,
};

pub const Event = union(enum) {
    // generic events
    quit,
    screen_resize: Size,

    // mouse events
    mouse_motion: MouseMotionEvent,
    mouse_down: MouseButton,
    mouse_up: MouseButton,

    // keyboard events
    key_down: KeyEvent,
    key_up: KeyEvent,
    text_input: InputEvent,

    pub const MouseMotionEvent = struct {
        position: Point,
        delta: Point,
    };

    pub const KeyEvent = struct {
        scancode: u16,
    };

    pub const InputEvent = struct {
        text: []const u8,
    };
};

pub fn pollEvent(self: *Self) !?Event {
    return try self.backend.pollEvent();
}

pub const ScreenMapping = struct {
    display: *Self,

    width: usize,
    height: usize,
    stride: usize,
    pixels: [*]align(4) Color,

    pub fn unmap(self: *ScreenMapping) void {
        self.display.backend.unmapScreen(self.*);
        self.* = undefined;
    }
};

pub fn mapScreen(self: *Self) !ScreenMapping {
    return self.backend.mapScreen();
}

const Backend = switch (build_options.render_backend) {
    .sdl2 => Sdl2Backend,
    .dri => @compileError("Unimplemented render backend!"),
};

const Sdl2Backend = struct {
    window: sdl.Window,
    renderer: sdl.Renderer,
    texture: sdl.Texture,
    text_input_buffer: [32:0]u8,

    fn init(allocator: *std.mem.Allocator) !Sdl2Backend {
        try sdl.init(.{ .events = true, .video = true });

        var window = try sdl.createWindow("Dunstblick", .centered, .centered, 1280, 720, .{});
        errdefer window.destroy();

        var renderer = try sdl.createRenderer(window, null, .{
            .accelerated = true,
            .present_vsync = true,
            .target_texture = true,
        });
        errdefer renderer.destroy();

        const actual_size = window.getSize();

        var texture = try sdl.createTexture(
            renderer,
            .rgbx8888,
            .streaming,
            @intCast(usize, actual_size.width),
            @intCast(usize, actual_size.height),
        );
        errdefer texture.destroy();

        return Sdl2Backend{
            .window = window,
            .renderer = renderer,
            .texture = texture,
            .text_input_buffer = undefined,
        };
    }

    fn deinit(self: *Sdl2Backend) void {
        self.* = undefined;
        sdl.quit();
    }

    fn mapScreen(self: *Sdl2Backend) !ScreenMapping {
        var texture_info = try self.texture.query();
        var pixel_data = try self.texture.lock(null);
        return ScreenMapping{
            .display = @fieldParentPtr(Self, "backend", self),
            .width = texture_info.width,
            .height = texture_info.height,
            .stride = pixel_data.stride,
            .pixels = @ptrCast([*]Color, @alignCast(4, pixel_data.pixels)),
        };
    }

    fn unmapScreen(self: *Sdl2Backend, screen: ScreenMapping) void {
        var pixel_data = sdl.Texture.PixelData{
            .texture = self.texture.ptr,
            .pixels = @ptrCast([*]u8, screen.pixels),
            .stride = screen.stride,
        };
        pixel_data.release();

        self.present() catch |e| log.err("failed to unmap screen pixels: {}", .{e});
    }

    fn present(self: *Sdl2Backend) !void {
        try self.renderer.copy(self.texture, null, null);
        self.renderer.present();
    }

    fn pollEvent(self: *Sdl2Backend) !?Event {
        return if (sdl.pollEvent()) |sdl_event| switch (sdl_event) {
            .quit => @as(Event, .quit),
            .mouse_motion => |ev| Event{ .mouse_motion = Event.MouseMotionEvent{
                .position = Point{ .x = @intCast(i16, ev.x), .y = @intCast(i16, ev.y) },
                .delta = Point{ .x = @intCast(i16, ev.xrel), .y = @intCast(i16, ev.yrel) },
            } },
            .mouse_button_down => |ev| Event{ .mouse_down = translateMouseButton(ev.button) orelse return null },
            .mouse_button_up => |ev| Event{ .mouse_up = translateMouseButton(ev.button) orelse return null },
            .key_down => |ev| Event{ .key_down = mapKeyEvent(ev) },
            .key_up => |ev| Event{ .key_up = mapKeyEvent(ev) },
            .text_input => |ev| Event{ .text_input = Event.InputEvent{ .text = self.bufferTextInput(ev.text) } },
            else => blk: {
                log.debug("unhandled event of type {s}", .{std.meta.tagName(sdl_event)});
                break :blk null;
            },
        } else null;
    }

    fn bufferTextInput(self: *Sdl2Backend, src: [32]u8) [:0]const u8 {
        const len = std.mem.indexOfScalar(u8, &src, 0) orelse src.len;
        std.mem.copy(u8, &self.text_input_buffer, &src);
        return self.text_input_buffer[0..len :0];
    }

    fn mapKeyEvent(ev: sdl.Event.KeyboardEvent) Event.KeyEvent {
        return Event.KeyEvent{
            .scancode = @intCast(u16, @enumToInt(ev.keysym.scancode)),
        };
    }

    fn translateMouseButton(button: u8) ?MouseButton {
        switch (button) {
            sdl.c.SDL_BUTTON_LEFT => return MouseButton.left,
            sdl.c.SDL_BUTTON_RIGHT => return MouseButton.right,
            else => return null,
        }
    }
};

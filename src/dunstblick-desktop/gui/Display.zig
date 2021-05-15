const std = @import("std");
const sdl = @import("sdl2");
const build_options = @import("build_options");
const log = std.log.scoped(.display);

const Self = @This();

const Framebuffer = @import("Framebuffer.zig");
const Point = @import("Point.zig");
const Size = @import("Size.zig");

pub const requires_softmouse = switch (build_options.render_backend) {
    .sdl2 => false,
    .drm => true,
};

allocator: *std.mem.Allocator,
alive: bool,
backend: Backend,

mouse_position: Point,
framebuffer: ?Framebuffer,
screen_size: Size,

pub fn init(allocator: *std.mem.Allocator) !Self {
    var self = Self{
        .allocator = allocator,
        .alive = true,
        .backend = try Backend.init(allocator),

        .mouse_position = Point{ .x = 0, .y = 0 },
        .screen_size = undefined,
        .framebuffer = null,
    };

    self.screen_size = self.backend.getScreenSize();
    self.mouse_position = Point{
        .x = @intCast(i16, self.screen_size.width / 2),
        .y = @intCast(i16, self.screen_size.height / 2),
    };

    return self;
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
    var maybe_event = try self.backend.pollEvent();
    if (maybe_event) |event| {
        switch (event) {
            .screen_resize => |size| self.screen_size = size,
            .mouse_motion => |motion| self.mouse_position = motion.position,
            else => {},
        }
    }
    return maybe_event;
}

pub fn mapScreen(self: *Self) !Framebuffer {
    std.debug.assert(self.framebuffer == null);
    self.framebuffer = try self.backend.mapScreen();
    return self.framebuffer.?;
}

pub fn unmapScreen(self: *Self) void {
    std.debug.assert(self.framebuffer != null);
    self.backend.unmapScreen(self.framebuffer.?);
    self.framebuffer = null;
}

const Backend = switch (build_options.render_backend) {
    .sdl2 => Sdl2Backend,
    .dri => @compileError("Unimplemented render backend!"),
};

const Sdl2Backend = struct {
    const texture_format = .argb8888;

    window: sdl.Window,
    renderer: sdl.Renderer,
    texture: sdl.Texture,
    text_input_buffer: [32:0]u8,

    fn init(allocator: *std.mem.Allocator) !Sdl2Backend {
        try sdl.init(.{ .events = true, .video = true });

        var window = try sdl.createWindow("Dunstblick", .centered, .centered, 1280, 720, .{
            .resizable = (std.builtin.cpu.arch == .aarch64), // TODO: Change to `true` when finished
            .shown = true,
        });
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
            texture_format,
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

    fn mapScreen(self: *Sdl2Backend) !Framebuffer {
        var texture_info = try self.texture.query();
        var pixel_data = try self.texture.lock(null);
        return Framebuffer{
            .width = texture_info.width,
            .height = texture_info.height,
            .stride = @divExact(pixel_data.stride, 4),
            .pixels = @ptrCast([*]Framebuffer.Color, @alignCast(4, pixel_data.pixels)),
        };
    }

    fn unmapScreen(self: *Sdl2Backend, screen: Framebuffer) void {
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
            .window => |ev| switch (ev.type) {
                // ignore size_changed events (those are "runtime scaling")
                .size_changed => @as(?Event, null),

                // only pass "resized" events (which are *after* the resizing is done)
                .resized => |size| blk: {
                    if (sdl.createTexture(
                        self.renderer,
                        texture_format,
                        .streaming,
                        @intCast(usize, size.width),
                        @intCast(usize, size.height),
                    )) |new_texture| {
                        self.texture.destroy();
                        self.texture = new_texture;
                    } else |err| {
                        log.err("failed to resize internal screen buffer: {s}", .{@errorName(err)});
                    }

                    break :blk Event{ .screen_resize = Size{
                        .width = @intCast(u15, size.width),
                        .height = @intCast(u15, size.height),
                    } };
                },
                else => blk: {
                    log.debug("unhandled event of type window.{s}", .{std.meta.tagName(ev.type)});
                    break :blk null;
                },
            },
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

    fn getScreenSize(self: Sdl2Backend) Size {
        var size = self.window.getSize();
        return Size{
            .width = @intCast(u15, size.width),
            .height = @intCast(u15, size.height),
        };
    }
};

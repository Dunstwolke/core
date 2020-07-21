const std = @import("std");
const args_parser = @import("args");
const sdl = @import("sdl2");
const uri = @import("uri");
const network = @import("network");

const app_discovery = @import("app-discovery.zig");
const painting = @import("painting.zig");

const protocol = @import("dunstblick-protocol");

usingnamespace @import("types.zig");

var test_icon: painting.Image = undefined;

fn findWindow(window_list: *std.TailQueue(UiContext), window_id: u32) ?*std.TailQueue(UiContext).Node {
    const win = sdl.Window.fromID(window_id) orelse return null;

    var it = window_list.first;
    return while (it) |c| : (it = c.next) {
        if (c.data.window.ptr == win.ptr)
            break c;
    } else null;
}

pub fn main() !u8 {
    var counter = std.testing.LeakCountAllocator.init(std.heap.c_allocator);
    defer {
        counter.validate() catch {};
    }

    const gpa = &counter.allocator;

    try network.init();
    defer network.deinit();

    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();

    app_discovery.init(gpa);
    try app_discovery.start();
    defer app_discovery.stop();

    try painting.init(gpa);
    defer painting.deinit();

    test_icon = try painting.Image.load(@embedFile("../images/kristall-32.png"));
    defer test_icon.deinit();

    var cursors: [sdl.c.SDL_NUM_SYSTEM_CURSORS]*sdl.c.SDL_Cursor = undefined;
    for (cursors) |*cursor, i| {
        cursor.* = sdl.c.SDL_CreateSystemCursor(@intToEnum(sdl.c.SDL_SystemCursor, @intCast(c_int, i))) orelse return sdl.makeError();
    }

    var currentCursor: sdl.c.SDL_SystemCursor = .SDL_SYSTEM_CURSOR_ARROW;
    sdl.c.SDL_SetCursor(cursors[@intCast(usize, @enumToInt(currentCursor))]);

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
        var sess = try DiscoverySession.create(gpa);
        errdefer sess.destroy();

        var context = try UiContext.init("Dunstblick Services", 480, 400);
        errdefer context.deinit();

        context.session = sess;

        const node = try gpa.create(UiNode);
        node.* = UiNode.init(context);

        window_list.append(node);
    }

    core_loop: while (window_list.len > 0) {
        while (sdl.pollNativeEvent()) |ev| {
            const event_type = @intToEnum(sdl.c.SDL_EventType, @intCast(c_int, ev.type));
            switch (event_type) {
                .SDL_QUIT => break :core_loop,
                .SDL_WINDOWEVENT => {
                    const win_ev = sdl.Event.from(ev).window;

                    const ctx = findWindow(&window_list, win_ev.window_id) orelse continue;

                    switch (win_ev.type) {
                        .close => {
                            window_list.remove(ctx);
                            ctx.data.deinit();
                            gpa.destroy(ctx);
                        },
                        .resized => |size| {
                            try ctx.data.resize(Size{
                                .width = @intCast(usize, size.width),
                                .height = @intCast(usize, size.height),
                            });
                            try ctx.data.render();
                        },
                        .size_changed => {},
                        else => std.log.debug(.app, "{} {}\n", .{ ctx.data.window, win_ev }),
                    }
                },
                .SDL_KEYDOWN, .SDL_KEYUP => {
                    const ctx = findWindow(&window_list, ev.key.windowID) orelse continue;
                    ctx.data.pushEvent(ev);
                },
                .SDL_MOUSEBUTTONUP, .SDL_MOUSEBUTTONDOWN => {
                    const ctx = findWindow(&window_list, ev.button.windowID) orelse continue;
                    ctx.data.pushEvent(ev);
                },
                .SDL_MOUSEMOTION => {
                    const ctx = findWindow(&window_list, ev.motion.windowID) orelse continue;
                    ctx.data.pushEvent(ev);
                },
                .SDL_MOUSEWHEEL => {
                    const ctx = findWindow(&window_list, ev.wheel.windowID) orelse continue;
                    ctx.data.pushEvent(ev);
                },
                else => std.log.warn(.app, "Unhandled event: {}\n", .{
                    event_type,
                }),
            }
        }

        {
            var it = window_list.first;
            while (it) |ctx| : (it = ctx.next) {
                it = ctx.next;

                ctx.data.update();
                if (!ctx.data.alive) {
                    window_list.remove(ctx);
                    ctx.data.deinit();
                    gpa.destroy(ctx);
                }
            }
        }

        {
            var it = window_list.first;
            while (it) |ctx| : (it = ctx.next) {
                try ctx.data.render();
            }
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
    screen_size: Size,
    session: ?*DiscoverySession = null,

    alive: bool = true,

    const backbuffer_format = .abgr8888;

    fn init(title: [:0]const u8, width: u32, height: u32) !Self {
        var win = try sdl.createWindow(
            "Dunstblick Services",
            .{ .centered = {} },
            .{ .centered = {} },
            width,
            height,
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
            .screen_size = Size{
                .width = width,
                .height = height,
            },
        };
    }

    fn deinit(self: *Self) void {
        if (self.session) |session| {
            session.destroy();
        }
        self.back_buffer.destroy();
        self.renderer.destroy();
        self.window.destroy();
        self.* = undefined;
    }

    fn resize(self: *Self, new_size: Size) !void {
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

    fn update(self: *Self) void {
        if (self.session) |session| {
            self.alive = session.update() catch false;
        }
    }

    fn pushEvent(self: *Self, event: sdl.c.SDL_Event) void {
        if (self.session) |session| {
            session.pushEvent(event);
        }
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

const UiNode = std.TailQueue(UiContext).Node;

const cpp = struct {
    pub const ZigSession = @Type(.Opaque);
    pub const Object = @Type(.Opaque);

    pub extern fn session_pushEvent(current_session: *ZigSession, e: *const sdl.c.SDL_Event) void;

    pub extern fn session_getCursor(session: *ZigSession) sdl.c.SDL_SystemCursor;

    pub extern fn session_render(session: *ZigSession, screen_rect: Rectangle, painter: *painting.PainterAPI) void;

    // ZigSession Class

    /// Callback interface for the C++ code
    pub const ZigSessionApi = extern struct {
        const Self = @This();

        trigger_event: fn (api: *Self, event: protocol.EventID, widget: protocol.WidgetName) callconv(.C) void,

        trigger_propertyChanged: fn (api: *Self, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const protocol.Value) callconv(.C) void,
    };

    pub extern fn zsession_create(api: *ZigSessionApi) ?*ZigSession;

    pub extern fn zsession_destroy(session: *ZigSession) void;

    pub extern fn zsession_uploadResource(session: *ZigSession, resource_id: protocol.ResourceID, kind: protocol.ResourceKind, data: [*]const u8, len: usize) void;

    pub extern fn zsession_addOrUpdateObject(session: *ZigSession, obj: *Object) void;

    pub extern fn zsession_setView(session: *ZigSession, id: protocol.ResourceID) void;

    pub extern fn zsession_setRoot(session: *ZigSession, obj: protocol.ObjectID) void;

    pub extern fn zsession_setProperty(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName, value: *const protocol.Value) void;

    pub extern fn zsession_clear(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName) void;

    pub extern fn zsession_insertRange(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName, index: usize, count: usize, values: [*]const protocol.ObjectID) void;

    pub extern fn zsession_removeRange(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName, index: usize, count: usize) void;

    pub extern fn zsession_moveRange(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName, indexFrom: usize, indexTo: usize, count: usize) void;

    pub extern fn object_create(id: protocol.ObjectID) ?*Object;

    pub extern fn object_addProperty(object: *Object, prop: protocol.PropertyName, value: *const protocol.Value) bool;

    pub extern fn object_destroy(object: *Object) void;
};

const DiscoverySession = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    cpp_session: *cpp.ZigSession,
    api: cpp.ZigSessionApi,

    alive: bool = true,

    const resource_names = struct {
        const discovery_menu = @intToEnum(protocol.ResourceID, 1);
        const discovery_list_item = @intToEnum(protocol.ResourceID, 2);
    };

    const object_names = struct {
        const root = @intToEnum(protocol.ObjectID, 1);
    };

    const properties = struct {
        const local_discovery_list = @intToEnum(protocol.PropertyName, 1);
        const local_app_name = @intToEnum(protocol.PropertyName, 2);
        const local_app_ip = @intToEnum(protocol.PropertyName, 3);
        const local_app_port = @intToEnum(protocol.PropertyName, 4);
        const local_app_id = @intToEnum(protocol.PropertyName, 5);
    };

    const events = struct {
        const local_exit_client_event = @intToEnum(protocol.EventID, 1);
        const local_open_session_event = @intToEnum(protocol.EventID, 2);
        const local_close_session_event = @intToEnum(protocol.EventID, 3);
    };

    /// Must be a non-moveable object → heap allocate
    pub fn create(allocator: *std.mem.Allocator) !*Self {
        var session = try allocator.create(Self);
        errdefer allocator.destroy(session);

        session.* = Self{
            .allocator = allocator,
            .cpp_session = undefined,
            .api = cpp.ZigSessionApi{
                .trigger_event = zsession_triggerEvent,
                .trigger_propertyChanged = zsession_triggerPropertyChanged,
            },
        };

        session.cpp_session = cpp.zsession_create(&session.api) orelse return error.OutOfMemory;

        const root_layout: []const u8 = @embedFile("./layouts/discovery-menu.cui");
        cpp.zsession_uploadResource(
            session.cpp_session,
            resource_names.discovery_menu,
            .layout,
            root_layout.ptr,
            root_layout.len,
        );

        const item_layout: []const u8 = @embedFile("./layouts/discovery-list-item.cui");
        cpp.zsession_uploadResource(
            session.cpp_session,
            resource_names.discovery_list_item,
            .layout,
            item_layout.ptr,
            item_layout.len,
        );

        cpp.zsession_setView(
            session.cpp_session,
            resource_names.discovery_menu,
        );

        {
            const obj = cpp.object_create(object_names.root) orelse return error.OutOfMemory;
            errdefer cpp.object_destroy(obj);

            const success = cpp.object_addProperty(obj, properties.local_discovery_list, &protocol.Value{
                .type = .objectlist,
                .value = undefined,
            });
            std.debug.assert(success == true);

            cpp.zsession_addOrUpdateObject(session.cpp_session, obj);
        }

        cpp.zsession_setRoot(
            session.cpp_session,
            object_names.root,
        );

        return session;
    }

    pub fn destroy(self: *Self) void {
        cpp.zsession_destroy(self.cpp_session);
        self.allocator.destroy(self);
    }

    fn pushEvent(self: *Self, event: sdl.c.SDL_Event) void {
        cpp.session_pushEvent(self.cpp_session, &event);
    }

    pub fn update(self: *Self) !bool {
        var list = app_discovery.getDiscovereyApplications();
        defer list.release();

        var app_ids = std.ArrayList(protocol.ObjectID).init(self.allocator);
        defer app_ids.deinit();

        for (list.applications) |app, i| {
            const id = @intToEnum(protocol.ObjectID, @intCast(u32, 1000 + i));

            {
                const obj = cpp.object_create(id) orelse return error.OutOfMemory;
                errdefer cpp.object_destroy(obj);

                if (cpp.object_addProperty(obj, properties.local_app_name, &protocol.Value{
                    .type = .string,
                    .value = .{
                        .string = app.name.ptr,
                    },
                }) == false) {
                    return error.FailedToAddProperty;
                }

                if (cpp.object_addProperty(obj, properties.local_app_port, &protocol.Value{
                    .type = .integer,
                    .value = .{
                        .integer = app.tcp_port,
                    },
                }) == false) {
                    return error.FailedToAddProperty;
                }

                var addr_buf: [256]u8 = undefined;
                var ip_str = std.fmt.bufPrint(&addr_buf, "{}\x00", .{app.address}) catch unreachable;

                if (cpp.object_addProperty(obj, properties.local_app_ip, &protocol.Value{
                    .type = .string,
                    .value = .{
                        // space should be sufficient for both IPv4 and IPv6
                        .string = @ptrCast([*:0]const u8, &addr_buf),
                    },
                }) == false) {
                    return error.FailedToAddProperty;
                }

                if (cpp.object_addProperty(obj, properties.local_app_id, &protocol.Value{
                    .type = .name,
                    .value = .{
                        .name = @intToEnum(protocol.WidgetName, @intCast(u32, i + 1)),
                    },
                }) == false) {
                    return error.FailedToAddProperty;
                }

                cpp.zsession_addOrUpdateObject(self.cpp_session, obj);
            }

            try app_ids.append(id);
        }

        cpp.zsession_clear(self.cpp_session, object_names.root, properties.local_discovery_list);
        cpp.zsession_insertRange(self.cpp_session, object_names.root, properties.local_discovery_list, 0, app_ids.items.len, app_ids.items.ptr);
        return self.alive;
    }

    fn zsession_triggerEvent(api: *cpp.ZigSessionApi, event: protocol.EventID, widget: protocol.WidgetName) callconv(.C) void {
        const self = @fieldParentPtr(Self, "api", api);
        switch (event) {
            events.local_exit_client_event => self.alive = false,

            events.local_open_session_event => {
                std.debug.print("open session for {}\n", .{@enumToInt(widget)});
            },

            else => std.debug.print("zsession_triggerEvent: {} {}\n", .{ event, widget }),
        }
        //         else if (event == local_open_session_event) {
        //             DiscoveredClient client;
        //             {
        //                 std::lock_guard<std::mutex> lock{discovered_clients_lock};
        //                 if (widget.value < 1 or widget.value > discovered_clients.size())
        //                     return;

        //                 client = discovered_clients.at(widget.value - 1);
        //             }

        //             auto const net_sess = new NetworkSession(client.create_tcp_endpoint());

        //             all_sessions.emplace_back(net_sess);

        //         } else if (event == local_close_session_event) {

        //         }
    }

    fn zsession_triggerPropertyChanged(api: *cpp.ZigSessionApi, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const protocol.Value) callconv(.C) void {
        std.debug.print("zsession_triggerPropertyChanged: {} {} {}\n", .{ oid, name, value });
    }
};

fn runPainterDemo(fb: anytype) void {
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

    fb.drawIcon(test_icon, Rectangle{
        .x = 0,
        .y = 380,
        .width = 240,
        .height = 240,
    });
}

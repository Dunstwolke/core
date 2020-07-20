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

        var context = try UiContext.init("Dunstblick Services", 240, 400);
        errdefer context.deinit();

        context.session = sess;

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
                            try ctx.data.resize(Size{
                                .width = @intCast(usize, size.width),
                                .height = @intCast(usize, size.height),
                            });
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
            self.alive = session.update();
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

            // runPainterDemo(&fb);

            var list = app_discovery.getDiscovereyApplications();
            defer list.release();

            for (list.applications) |app, i| {
                fb.drawString(app.name, Rectangle{
                    .x = 240,
                    .y = 10 + 40 * @intCast(isize, i),
                    .width = 200,
                    .height = 40,
                }, .monospace, .center);
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

    pub extern fn zsession_setView(session: *ZigSession, id: protocol.ResourceID) void;

    pub extern fn zsession_setRoot(session: *ZigSession, obj: protocol.ObjectID) void;
};

const DiscoverySession = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    cpp_session: *cpp.ZigSession,
    api: cpp.ZigSessionApi,

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

        //         Object obj{local_root_obj};
        //         obj.add(local_discovery_list, ObjectList{});
        //         sess.addOrUpdateObject(std::move(obj));

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

    pub fn update(self: *Self) bool {

        //     std::vector<DiscoveredClient> clients;
        //     {
        //         std::lock_guard<std::mutex> lock{discovered_clients_lock};
        //         clients = discovered_clients;
        //     }

        //     ObjectList list;
        //     list.reserve(clients.size());

        //     for (size_t i = 0; i < clients.size(); i++) {
        //         auto const id = local_session_id(i);

        //         Object obj{id};

        //         obj.add(local_app_name, UIValue(clients[i].name));
        //         obj.add(local_app_port, UIValue(clients[i].tcp_port));
        //         obj.add(local_app_ip, UIValue(xnet::to_string(clients[i].udp_ep, false)));
        //         obj.add(local_app_id, UIValue(WidgetName(i + 1)));

        //         list.emplace_back(obj);

        //         sess.addOrUpdateObject(std::move(obj));
        //     }

        //     sess.clear(local_root_obj, local_discovery_list);
        //     sess.insertRange(local_root_obj, local_discovery_list, 0, list.size(), list.data());
        return true;
    }

    fn zsession_triggerEvent(api: *cpp.ZigSessionApi, event: protocol.EventID, widget: protocol.WidgetName) callconv(.C) void {
        //         if (event == local_exit_client_event) {
        //             shutdown_app_requested = true;
        //         } else if (event == local_open_session_event) {
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

        //         } else {
        //             fprintf(stderr, "Unknown event: %lu, Sender: %lu\n", event.value, widget.value);
        //             // assert(false and "unhandled event detected");
        //         }
    }

    fn zsession_triggerPropertyChanged(api: *cpp.ZigSessionApi, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const protocol.Value) callconv(.C) void {
        unreachable;
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

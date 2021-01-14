const std = @import("std");
const args_parser = @import("args");
const sdl = @import("sdl2");
const uri = @import("uri");
const network = @import("network");

const log = std.log.scoped(.app);

const painting = @import("painting.zig");
const app_discovery = @import("app-discovery.zig");

const protocol = @import("dunstblick-protocol");

const cpp = @import("cpp.zig");

const Session = @import("session.zig").Session;
const DiscoverySession = @import("discovery-session.zig").DiscoverySession;

const Window = @import("window.zig").Window;
const WindowCollection = @import("window-collection.zig").WindowCollection;

usingnamespace @import("types.zig");

pub fn main() !u8 {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();

    const gpa = &gpa_state.allocator;

    try network.init();
    defer network.deinit();

    try sdl.init(sdl.InitFlags.everything);
    defer sdl.quit();

    app_discovery.init(gpa);
    try app_discovery.start();
    defer app_discovery.stop();

    try painting.init(gpa);
    defer painting.deinit();

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

    var windows = WindowCollection.init(gpa);
    defer windows.deinit();

    if (cli.options.discovery.?) {
        var sess = try DiscoverySession.create(gpa, &windows);
        errdefer sess.destroy();

        _ = try windows.addWindow("Dunstblick Applications", 480, 400, &sess.driver);
    }

    core_loop: while (windows.window_list.len > 0) {
        while (sdl.pollNativeEvent()) |ev| {
            const event_type = @intToEnum(sdl.c.SDL_EventType, @intCast(c_int, ev.type));
            switch (event_type) {
                .SDL_QUIT => break :core_loop,
                .SDL_WINDOWEVENT => {
                    const win_ev = sdl.Event.from(ev).window;

                    const ctx = windows.find(win_ev.window_id) orelse continue;

                    switch (win_ev.type) {
                        .close => {
                            windows.close(ctx);
                        },
                        .resized => |size| {
                            try ctx.data.resize(Size{
                                .width = @intCast(usize, size.width),
                                .height = @intCast(usize, size.height),
                            });
                            try ctx.data.render();
                        },
                        .size_changed => {},
                        else => log.debug("{} {}\n", .{ ctx.data.window, win_ev }),
                    }
                },
                .SDL_KEYDOWN, .SDL_KEYUP => {
                    const ctx = windows.find(ev.key.windowID) orelse continue;
                    ctx.data.pushEvent(ev);
                },
                .SDL_MOUSEBUTTONUP, .SDL_MOUSEBUTTONDOWN => {
                    const ctx = windows.find(ev.button.windowID) orelse continue;
                    ctx.data.pushEvent(ev);
                },
                .SDL_MOUSEMOTION => {
                    const ctx = windows.find(ev.motion.windowID) orelse continue;
                    ctx.data.pushEvent(ev);
                },
                .SDL_MOUSEWHEEL => {
                    const ctx = windows.find(ev.wheel.windowID) orelse continue;
                    ctx.data.pushEvent(ev);
                },
                else => log.warn("Unhandled event: {}\n", .{
                    event_type,
                }),
            }

            {
                // remove all dead sessions
                var it = windows.window_list.first;
                while (it) |ctx| : (it = ctx.next) {
                    it = ctx.next;
                    if (!ctx.data.alive) {
                        windows.close(ctx);
                    }
                }
            }
        }

        {
            var it = windows.window_list.first;
            while (it) |ctx| : (it = ctx.next) {
                it = ctx.next;

                ctx.data.update();
                if (!ctx.data.alive) {
                    windows.close(ctx);
                }
            }
        }

        {
            var it = windows.window_list.first;
            while (it) |ctx| : (it = ctx.next) {
                try ctx.data.render();
            }
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

// fn runPainterDemo(fb: anytype) void {
//     fb.drawHLine(10, 10, 220, .edge);
//     fb.drawHLine(10, 30, 220, .crease);

//     fb.drawVLine(10, 40, 220, .edge);
//     fb.drawVLine(230, 40, 220, .crease);

//     // filled rectangles

//     fb.fillRectangle(Rectangle{
//         .x = 25,
//         .y = 45,
//         .width = 40,
//         .height = 40,
//     }, .highlight);

//     fb.fillRectangle(Rectangle{
//         .x = 75,
//         .y = 45,
//         .width = 40,
//         .height = 40,
//     }, .background);

//     fb.fillRectangle(Rectangle{
//         .x = 125,
//         .y = 45,
//         .width = 40,
//         .height = 40,
//     }, .input_field);

//     fb.fillRectangle(Rectangle{
//         .x = 175,
//         .y = 45,
//         .width = 40,
//         .height = 40,
//     }, .checkered);

//     // rectangle outlines

//     fb.drawRectangle(Rectangle{
//         .x = 25,
//         .y = 95,
//         .width = 40,
//         .height = 40,
//     }, .edge);

//     fb.drawRectangle(Rectangle{
//         .x = 75,
//         .y = 95,
//         .width = 40,
//         .height = 40,
//     }, .crease);

//     fb.drawRectangle(Rectangle{
//         .x = 125,
//         .y = 95,
//         .width = 40,
//         .height = 40,
//     }, .raised);

//     fb.drawRectangle(Rectangle{
//         .x = 175,
//         .y = 95,
//         .width = 40,
//         .height = 40,
//     }, .sunken);

//     fb.drawRectangle(Rectangle{
//         .x = 25,
//         .y = 145,
//         .width = 40,
//         .height = 40,
//     }, .input_field);

//     fb.drawRectangle(Rectangle{
//         .x = 75,
//         .y = 145,
//         .width = 40,
//         .height = 40,
//     }, .button_default);

//     fb.drawRectangle(Rectangle{
//         .x = 125,
//         .y = 145,
//         .width = 40,
//         .height = 40,
//     }, .button_active);

//     fb.drawRectangle(Rectangle{
//         .x = 175,
//         .y = 145,
//         .width = 40,
//         .height = 40,
//     }, .button_pressed);

//     fb.drawString("¡Hello, Wörld!", Rectangle{
//         .x = 25,
//         .y = 195,
//         .width = 190,
//         .height = 40,
//     }, .sans, .left);

//     fb.drawString("¡Hello, Wörld!", Rectangle{
//         .x = 25,
//         .y = 215,
//         .width = 190,
//         .height = 40,
//     }, .serif, .right);

//     fb.drawString("¡Hello, Wörld!", Rectangle{
//         .x = 25,
//         .y = 235,
//         .width = 190,
//         .height = 40,
//     }, .monospace, .center);

//     fb.drawString(
//         \\Li Europan lingues es membres
//         \\del sam familie. Lor separat
//         \\existentie es un myth. Por
//         \\scientie, musica, sport etc,
//         \\litot Europa usa li sam vocabular.
//         \\Li lingues differe solmen in li
//     , Rectangle{
//         .x = 10,
//         .y = 260,
//         .width = 220,
//         .height = 80,
//     }, .sans, .left);

//     fb.drawIcon(test_icon, Rectangle{
//         .x = 0,
//         .y = 380,
//         .width = 240,
//         .height = 240,
//     });
// }

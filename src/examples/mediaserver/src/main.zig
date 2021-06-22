const std = @import("std");
const dunstblick = @import("dunstblick");
const data = @import("app-data");

const c = @import("c.zig");

fn hiword(val: u32) u16 {
    return @truncate(u16, val >> 16);
}

fn loword(val: u32) u16 {
    return @truncate(u16, val >> 16);
}

// HLS definitions (copied from BASSHLS.H)
const BASS_SYNC_HLS_SEGMENT = 0x10300;
const BASS_TAG_HLS_EXTINF = 0x14000;

const ROOT_OBJ = 1;

pub fn main() anyerror!u8 {
    var stderr = std.io.getStdErr().writer();

    if (hiword(c.BASS_GetVersion()) != c.BASSVERSION) {
        try stderr.writeAll("An incorrect version of BASS was loaded!\n");
        return 1;
    }

    // initialize default output device
    if (c.BASS_Init(-1, 44100, 0, null, null) == 0) {
        try stderr.writeAll("Can't initialize device");
        return 1;
    }
    defer _ = c.BASS_Free();

    _ = c.BASS_SetConfig(c.BASS_CONFIG_NET_PLAYLIST, 1); // enable playlist processing
    _ = c.BASS_SetConfig(c.BASS_CONFIG_NET_PREBUF_WAIT, 0); // disable BASS_StreamCreateURL pre-buffering

    _ = c.BASS_PluginLoad("libbass_aac.so", 0); // load BASS_AAC (if present) for AAC support
    _ = c.BASS_PluginLoad("libbassflac.so", 0); // load BASSFLAC (if present) for FLAC support
    _ = c.BASS_PluginLoad("libbasshls.so", 0); // load BASSHLS (if present) for HLS support

    const icon = @embedFile("../resources/disc-player.tvg");

    var app = try dunstblick.Application.open(
        std.heap.c_allocator,
        "MediaPlayer",
        "A small media player with a music library.",
        icon,
    );
    defer app.close();

    // _ = c.dunstblick_SetConnectedCallback(dbProvider, clientConnected, null);
    // _ = c.dunstblick_SetDisconnectedCallback(dbProvider, clientDisconnected, null);

    inline for (std.meta.declarations(data.resources)) |decl| {
        const res = @field(data.resources, decl.name);
        try app.addResource(res.id, res.kind, res.data);
    }

    //try openURL("http://sentinel.scenesat.com:8000/scenesatmax");
    try openFile("/dunstwolke/music/albums/Morgan Willis/Supernova/Morgan Willis - Supernova - 01 Opening (Vocal Marko Maric).mp3");

    while (true) {
        if (try app.pollEvent(null)) |event| {
            switch (event.*) {
                .connected => |event_args| {
                    const con = event_args.connection;
                    try con.setView(data.resources.main.id);

                    var root_obj = try con.beginChangeObject(data.objects.root);
                    errdefer root_obj.cancel();

                    try root_obj.setProperty(data.properties.@"current-song", .{
                        .string = dunstblick.String.readOnly("Current Song"),
                    });

                    try root_obj.setProperty(data.properties.@"current-artist", .{
                        .string = dunstblick.String.readOnly("Current Artist"),
                    });

                    try root_obj.setProperty(data.properties.@"current-albumart", .{
                        .resource = data.resources.album_placeholder.id,
                    });

                    try root_obj.commit();

                    try con.setRoot(data.objects.root);
                },
                .disconnected => {
                    //
                },
                .widget_event => |event_args| {
                    switch (event_args.event) {
                        data.events.@"next-song" => {},
                        data.events.@"previous-song" => {},
                        data.events.@"open-volume-control" => {},
                        data.events.@"play-pause" => {},
                        data.events.@"open-main-menu" => {
                            try event_args.connection.setView(data.resources.menu.id);
                        },
                        data.events.@"open-settings" => {},
                        data.events.@"open-albums" => {},
                        data.events.@"open-radio" => {},
                        data.events.@"open-playlists" => {},
                        data.events.@"toggle-shuffle" => {},
                        data.events.@"toggle-repeat-one" => {},
                        data.events.@"toggle-repeat-all" => {},
                        data.events.@"close-main-menu" => {
                            try event_args.connection.setView(data.resources.main.id);
                        },
                        else => {}, // ignore
                    }
                },
                .property_changed => {
                    //
                },
            }
        }
    }

    return 0;
}

var chan: c.HSTREAM = 0;

fn playChannel(ch: c.HSTREAM) !void {
    _ = c.BASS_StreamFree(chan); // close old stream

    chan = ch;

    // set syncs for stream title updates
    _ = c.BASS_ChannelSetSync(chan, c.BASS_SYNC_META, 0, doMeta, null); // Shoutcast
    _ = c.BASS_ChannelSetSync(chan, c.BASS_SYNC_OGG_CHANGE, 0, doMeta, null); // Icecast/OGG
    _ = c.BASS_ChannelSetSync(chan, BASS_SYNC_HLS_SEGMENT, 0, doMeta, null); // HLS

    // set sync for stalling/buffering
    _ = c.BASS_ChannelSetSync(chan, c.BASS_SYNC_STALL, 0, stallSync, null);
    // set sync for end of stream
    _ = c.BASS_ChannelSetSync(chan, c.BASS_SYNC_END, 0, endSync, null);
    // play it!
    _ = c.BASS_ChannelPlay(chan, c.FALSE);

    doMeta(0, chan, 0, null);
}

fn openURL(url: [*:0]const u8) !void {
    const ch = c.BASS_StreamCreateURL(url, 0, c.BASS_STREAM_BLOCK | c.BASS_STREAM_STATUS | c.BASS_STREAM_AUTOFREE, null, null);
    if (ch == 0)
        return error.StreamNotFound;
    try playChannel(ch);
}

fn openFile(url: [*:0]const u8) !void {
    const ch = c.BASS_StreamCreateFile(c.FALSE, url, 0, 0, 0);
    if (ch == 0)
        return error.FileNotFound;
    try playChannel(ch);
}

fn endSync(handle: c.HSYNC, channel: c.DWORD, bits: c.DWORD, user: ?*c_void) callconv(.C) void {
    _ = handle;
    _ = channel;
    _ = bits;
    _ = user;
    std.io.getStdErr().writer().writeAll("end sync\n") catch {};
}

fn stallSync(handle: c.HSYNC, channel: c.DWORD, bits: c.DWORD, user: ?*c_void) callconv(.C) void {
    _ = handle;
    _ = channel;
    _ = bits;
    _ = user;
    std.io.getStdErr().writer().writeAll("stall sync\n") catch {};
}

// update stream title from metadata
fn doMeta(handle: c.HSYNC, channel: c.DWORD, bits: c.DWORD, user: ?*c_void) callconv(.C) void {
    _ = handle;
    _ = channel;
    _ = bits;
    _ = user;

    _ = user;
    if (c.BASS_ChannelGetTags(channel, c.BASS_TAG_ID3)) |raw| {
        const id3 = @ptrCast(*const c.TAG_ID3, raw);
        std.debug.warn("got id3: {s}\n", .{id3});
    }

    if (c.BASS_ChannelGetTags(channel, c.BASS_TAG_ID3V2)) |raw| {
        std.debug.warn("got id3v2: {s}\n", .{raw});
    }

    if (c.BASS_ChannelGetTags(channel, c.BASS_TAG_META)) |raw| {
        std.debug.warn("got shoutcast: {s}\n", .{@ptrCast([*:0]const u8, raw)});
    }

    if (c.BASS_ChannelGetTags(channel, c.BASS_TAG_OGG)) |raw| {
        std.debug.warn("got icecast: {s}\n", .{raw});
    }

    if (c.BASS_ChannelGetTags(channel, BASS_TAG_HLS_EXTINF)) |raw| {
        std.debug.warn("got hls segment: {s}\n", .{raw});
    }
}

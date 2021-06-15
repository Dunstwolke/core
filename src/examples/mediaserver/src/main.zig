const std = @import("std");
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

fn addResource(provider: *c.dunstblick_Provider, index: u32, kind: c.dunstblick_ResourceKind, bits: []const u8) !void {
    const err = c.dunstblick_AddResource(
        provider,
        index,
        kind,
        bits.ptr,
        @intCast(u32, bits.len),
    );
    if (err != .DUNSTBLICK_ERROR_NONE)
        return error.DunstblickError;
}

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
    var dbProvider = if (c.dunstblick_OpenProvider(
        "MediaPlayer",
        "A small media player with a music library.",
        icon,
        icon.len,
    )) |player| player else {
        try stderr.writeAll("Could not initialize dunstblick provider!\n");
        return 2;
    };
    defer c.dunstblick_CloseProvider(dbProvider);

    _ = c.dunstblick_SetConnectedCallback(dbProvider, clientConnected, null);
    _ = c.dunstblick_SetDisconnectedCallback(dbProvider, clientDisconnected, null);

    inline for (std.meta.declarations(data.resources)) |decl| {
        const res = @field(data.resources, decl.name);

        try addResource(dbProvider, @enumToInt(res.id), switch (res.kind) {
            .layout => .DUNSTBLICK_RESOURCE_LAYOUT,
            .bitmap => .DUNSTBLICK_RESOURCE_BITMAP,
            .drawing => .DUNSTBLICK_RESOURCE_DRAWING,
            _ => unreachable,
        }, res.data);
    }

    //try openURL("http://sentinel.scenesat.com:8000/scenesatmax");
    try openFile("/dunstwolke/music/albums/Morgan Willis/Supernova/Morgan Willis - Supernova - 01 Opening (Vocal Marko Maric).mp3");

    while (true) {
        const err = c.dunstblick_WaitEvents(dbProvider);
        if (err != .DUNSTBLICK_ERROR_NONE) {
            try stderr.print("Failed to get event: {}!\n", .{err});
            return 3;
        }
    }

    return 0;
}

fn clientEvent(
    connection: ?*c.dunstblick_Connection,
    event: c.dunstblick_EventID,
    widget: c.dunstblick_WidgetName,
    user_data: ?*c_void,
) callconv(.C) void {
    std.debug.warn("event: {} {}\n", .{ event, widget });
    switch (event) {
        @enumToInt(data.events.@"next-song") => {},
        @enumToInt(data.events.@"previous-song") => {},
        @enumToInt(data.events.@"open-volume-control") => {},
        @enumToInt(data.events.@"play-pause") => {},
        @enumToInt(data.events.@"open-main-menu") => {
            _ = c.dunstblick_SetView(connection, @enumToInt(data.resources.menu.id));
        },
        @enumToInt(data.events.@"open-settings") => {},
        @enumToInt(data.events.@"open-albums") => {},
        @enumToInt(data.events.@"open-radio") => {},
        @enumToInt(data.events.@"open-playlists") => {},
        @enumToInt(data.events.@"toggle-shuffle") => {},
        @enumToInt(data.events.@"toggle-repeat-one") => {},
        @enumToInt(data.events.@"toggle-repeat-all") => {},
        @enumToInt(data.events.@"close-main-menu") => {
            _ = c.dunstblick_SetView(connection, @enumToInt(data.resources.main.id));
        },
        else => {}, // ignore
    }
}

fn clientConnected(
    provider: ?*c.dunstblick_Provider,
    connection: ?*c.dunstblick_Connection,
    size: c.dunstblick_Size,
    capabilities: c.dunstblick_ClientCapabilities,
    user_data: ?*c_void,
) callconv(.C) void {
    std.debug.warn("hi: {} {}\n", .{
        size,
        capabilities,
    });

    _ = c.dunstblick_SetEventCallback(connection, clientEvent, null);

    _ = c.dunstblick_SetView(connection, 1000);

    if (c.dunstblick_BeginChangeObject(connection, ROOT_OBJ)) |obj| {
        errdefer _ = c.dunstblick_CancelObject(obj);

        _ = c.dunstblick_SetObjectProperty(obj, @enumToInt(data.properties.@"current-song"), &c.dunstblick_Value{
            .type = .DUNSTBLICK_TYPE_STRING,
            .value = .{
                .string = "Current Song",
            },
        });

        _ = c.dunstblick_SetObjectProperty(obj, @enumToInt(data.properties.@"current-artist"), &c.dunstblick_Value{
            .type = .DUNSTBLICK_TYPE_STRING,
            .value = .{
                .string = "Current Artist",
            },
        });

        // TODO: Workaround for (probably) #4295
        var val: c.dunstblick_Value = undefined;
        val = c.dunstblick_Value{
            .type = .DUNSTBLICK_TYPE_RESOURCE,
            .value = .{
                .resource = 22,
            },
        };
        std.debug.warn("val = {} / {}\n", .{ val, val.value.resource });
        _ = c.dunstblick_SetObjectProperty(obj, @enumToInt(data.properties.@"current-albumart"), &val);

        _ = c.dunstblick_CommitObject(obj);
    }
}

fn clientDisconnected(
    provider: ?*c.dunstblick_Provider,
    connection: ?*c.dunstblick_Connection,
    reason: c.dunstblick_DisconnectReason,
    user_data: ?*c_void,
) callconv(.C) void {
    std.debug.warn("bye: {}\n", .{reason});
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
    std.io.getStdErr().writer().writeAll("end sync\n") catch |err| {};
}

fn stallSync(handle: c.HSYNC, channel: c.DWORD, bits: c.DWORD, user: ?*c_void) callconv(.C) void {
    std.io.getStdErr().writer().writeAll("stall sync\n") catch |err| {};
}

// update stream title from metadata
fn doMeta(handle: c.HSYNC, channel: c.DWORD, bits: c.DWORD, user: ?*c_void) callconv(.C) void {
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

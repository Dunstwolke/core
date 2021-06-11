const std = @import("std");

const c = @import("c.zig");

fn hiword(val: u32) u16 {
    return @truncate(u16, val >> 16);
}

fn loword(val: u32) u16 {
    return @truncate(u16, val >> 16);
}

const resources = @import("resources.zig");

const properties = struct {
    pub const current_artist = 1;
    pub const current_song = 2;
    pub const current_albumart = 3;
};

const callbacks = struct {
    pub const next_song = 1;
    pub const previous_song = 2;
    pub const open_volume_control = 3;
    pub const play_pause = 4;
    pub const open_main_menu = 5;
    pub const open_settings = 6;
    pub const open_albums = 7;
    pub const open_radio = 8;
    pub const open_playlists = 9;
    pub const toggle_shuffle = 10;
    pub const toggle_repeat_one = 11;
    pub const toggle_repeat_all = 12;
    pub const close_main_menu = 13;
};

const views = struct {
    pub const layout_main = 1000;
    pub const layout_menu = 1001;
    pub const layout_searchlist = 1002;
    pub const layout_searchitem = 1003;
};

// HLS definitions (copied from BASSHLS.H)
const BASS_SYNC_HLS_SEGMENT = 0x10300;
const BASS_TAG_HLS_EXTINF = 0x14000;

const ROOT_OBJ = 1;

fn addResource(provider: *c.dunstblick_Provider, index: u32, kind: c.dunstblick_ResourceKind, data: []const u8) !void {
    const err = c.dunstblick_AddResource(
        provider,
        index,
        kind,
        data.ptr,
        @intCast(u32, data.len),
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

    try addResource(dbProvider, 2, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_volume_off);
    try addResource(dbProvider, 3, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_volume_low);
    try addResource(dbProvider, 4, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_volume_medium);
    try addResource(dbProvider, 5, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_volume_high);
    try addResource(dbProvider, 6, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_skip_previous);
    try addResource(dbProvider, 7, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_skip_next);
    try addResource(dbProvider, 8, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_play);
    try addResource(dbProvider, 9, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_pause);
    try addResource(dbProvider, 10, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_menu);
    try addResource(dbProvider, 11, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_settings);
    try addResource(dbProvider, 12, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_repeat_one);
    try addResource(dbProvider, 13, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_repeat_all);
    try addResource(dbProvider, 14, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_shuffle);
    try addResource(dbProvider, 15, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_album);
    try addResource(dbProvider, 16, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_playlist);
    try addResource(dbProvider, 17, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_radio);
    try addResource(dbProvider, 18, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_add);
    try addResource(dbProvider, 19, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_folder);
    try addResource(dbProvider, 20, .DUNSTBLICK_RESOURCE_BITMAP, resources.icon_close);
    try addResource(dbProvider, 22, .DUNSTBLICK_RESOURCE_BITMAP, resources.img_placeholder);
    try addResource(dbProvider, 23, .DUNSTBLICK_RESOURCE_BITMAP, resources.img_background);

    try addResource(dbProvider, 1000, .DUNSTBLICK_RESOURCE_LAYOUT, resources.layout_main);
    try addResource(dbProvider, 1001, .DUNSTBLICK_RESOURCE_LAYOUT, resources.layout_menu);
    try addResource(dbProvider, 1002, .DUNSTBLICK_RESOURCE_LAYOUT, resources.layout_searchlist);
    try addResource(dbProvider, 1003, .DUNSTBLICK_RESOURCE_LAYOUT, resources.layout_searchitem);

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
        callbacks.next_song => {},
        callbacks.previous_song => {},
        callbacks.open_volume_control => {},
        callbacks.play_pause => {},
        callbacks.open_main_menu => {
            _ = c.dunstblick_SetView(connection, views.layout_menu);
        },
        callbacks.open_settings => {},
        callbacks.open_albums => {},
        callbacks.open_radio => {},
        callbacks.open_playlists => {},
        callbacks.toggle_shuffle => {},
        callbacks.toggle_repeat_one => {},
        callbacks.toggle_repeat_all => {},
        callbacks.close_main_menu => {
            _ = c.dunstblick_SetView(connection, views.layout_main);
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

        _ = c.dunstblick_SetObjectProperty(obj, properties.current_song, &c.dunstblick_Value{
            .type = .DUNSTBLICK_TYPE_STRING,
            .value = .{
                .string = "Current Song",
            },
        });

        _ = c.dunstblick_SetObjectProperty(obj, properties.current_artist, &c.dunstblick_Value{
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
        _ = c.dunstblick_SetObjectProperty(obj, properties.current_albumart, &val);

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

fn endSync(handle: c.HSYNC, channel: c.DWORD, data: c.DWORD, user: ?*c_void) callconv(.C) void {
    std.io.getStdErr().writer().writeAll("end sync\n") catch |err| {};
}

fn stallSync(handle: c.HSYNC, channel: c.DWORD, data: c.DWORD, user: ?*c_void) callconv(.C) void {
    std.io.getStdErr().writer().writeAll("stall sync\n") catch |err| {};
}

// update stream title from metadata
fn doMeta(handle: c.HSYNC, channel: c.DWORD, data: c.DWORD, user: ?*c_void) callconv(.C) void {
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

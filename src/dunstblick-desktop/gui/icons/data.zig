const std = @import("std");
const tvg = @import("tvg");

// const builder = tvg.builder(.@"1/256", .default);

pub const demo_apps = struct {
    pub const archiver = @embedFile("archiver.tvg");
    pub const calculator = @embedFile("calculator.tvg");
    pub const mahjongg = @embedFile("mahjongg.tvg");
    pub const notes = @embedFile("notes.tvg");
    pub const text_editor = @embedFile("text-editor.tvg");
    pub const web_browser = @embedFile("web-browser.tvg");
    pub const zig = @embedFile("zig-mark.tvg");
};

fn rgb(comptime hex: *const [6]u8) tvg.Color {
    return tvg.Color.fromString(hex) catch unreachable;
}

fn rgba(comptime hex: *const [6]u8, comptime alpha: f32) tvg.Color {
    var c = rgb(hex);
    c.a = @floatToInt(u8, 255.0 * alpha);
    return c;
}

const dim_black = rgb("12181d");
const signal_red = rgb("910002");

/// If an app doesn't provide a icon, this is shown instead.
pub const app_placeholder = @embedFile("application.tvg");

fn rectangle(x: f32, y: f32, w: f32, h: f32) tvg.Rectangle {
    return tvg.Rectangle{ .x = x, .y = y, .width = w, .height = h };
}

pub const app_menu = blk: {
    @setEvalBranchQuota(10_000);

    var icon_data: [4069]u8 = undefined;

    var stream = std.io.fixedBufferStream(&icon_data);

    var builder = tvg.builder.create(stream.writer());

    builder.writeHeader(48, 48, .@"1/256", .u8888, .default) catch unreachable;

    builder.writeColorTable(&.{dim_black}) catch unreachable;

    builder.writeFillRectangles(.{ .flat = 0 }, &.{
        rectangle(8, 8, 8, 8),
        rectangle(20, 8, 8, 8),
        rectangle(32, 8, 8, 8),
        rectangle(8, 20, 8, 8),
        rectangle(20, 20, 8, 8),
        rectangle(32, 20, 8, 8),
        rectangle(8, 32, 8, 8),
        rectangle(20, 32, 8, 8),
        rectangle(32, 32, 8, 8),
    }) catch unreachable;

    const final_data = stream.getWritten();

    break :blk final_data[0..final_data.len].*;
};

pub const workspace = blk: {
    @setEvalBranchQuota(10_000);

    var icon_data: [4069]u8 = undefined;

    var stream = std.io.fixedBufferStream(&icon_data);

    var builder = tvg.builder.create(stream.writer());

    builder.writeHeader(48, 48, .@"1/256", .u8888, .default) catch unreachable;

    builder.writeColorTable(&.{dim_black}) catch unreachable;

    builder.writeFillRectangles(.{ .flat = 0 }, &.{
        rectangle(6, 10, 38, 12),
        rectangle(6, 24, 12, 14),
        rectangle(20, 24, 24, 14),
    }) catch unreachable;

    const final_data = stream.getWritten();

    break :blk final_data[0..final_data.len].*;
};

pub const workspace_add = blk: {
    @setEvalBranchQuota(10_000);

    var icon_data: [4069]u8 = undefined;

    var stream = std.io.fixedBufferStream(&icon_data);

    var builder = tvg.builder.create(stream.writer());

    builder.writeHeader(48, 48, .@"1/256", .u8888, .default) catch unreachable;

    builder.writeColorTable(&.{ dim_black, signal_red }) catch unreachable;

    builder.writeFillRectangles(.{ .flat = 0 }, &.{
        rectangle(6, 10, 38, 12),
        rectangle(6, 24, 12, 14),
        rectangle(20, 24, 24, 14),
    }) catch unreachable;

    builder.writeFillPath(.{ .flat = 1 }, &.{
        .{
            .start = .{ .x = 26, .y = 32 },
            .commands = &.{
                .{ .horiz = .{ .data = 32 } },
                .{ .vert = .{ .data = 26 } },
                .{ .horiz = .{ .data = 36 } },
                .{ .vert = .{ .data = 32 } },
                .{ .horiz = .{ .data = 42 } },
                .{ .vert = .{ .data = 36 } },
                .{ .horiz = .{ .data = 36 } },
                .{ .vert = .{ .data = 42 } },
                .{ .horiz = .{ .data = 32 } },
                .{ .vert = .{ .data = 36 } },
                .{ .horiz = .{ .data = 26 } },
            },
        },
    }) catch unreachable;

    const final_data = stream.getWritten();

    break :blk final_data[0..final_data.len].*;
};

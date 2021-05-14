const tvg = @import("tvg");

const builder = tvg.builder(.@"1/256", .default);

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

pub const app_menu = blk: {
    @setEvalBranchQuota(10_000);

    break :blk builder.header(48, 48) ++
        builder.colorTable(&[_]tvg.Color{dim_black}) ++
        builder.fillRectangles(9, .flat, 0) ++
        builder.rectangle(8, 8, 8, 8) ++
        builder.rectangle(20, 8, 8, 8) ++
        builder.rectangle(32, 8, 8, 8) ++
        builder.rectangle(8, 20, 8, 8) ++
        builder.rectangle(20, 20, 8, 8) ++
        builder.rectangle(32, 20, 8, 8) ++
        builder.rectangle(8, 32, 8, 8) ++
        builder.rectangle(20, 32, 8, 8) ++
        builder.rectangle(32, 32, 8, 8) ++
        builder.end_of_document;
};

pub const workspace = blk: {
    @setEvalBranchQuota(10_000);

    break :blk builder.header(48, 48) ++
        builder.colorTable(&[_]tvg.Color{dim_black}) ++
        builder.fillRectangles(3, .flat, 0) ++
        builder.rectangle(6, 10, 38, 12) ++
        builder.rectangle(6, 24, 12, 14) ++
        builder.rectangle(20, 24, 24, 14) ++
        builder.end_of_document;
};

pub const workspace_add = blk: {
    @setEvalBranchQuota(10_000);

    break :blk builder.header(48, 48) ++
        builder.colorTable(&[_]tvg.Color{ dim_black, signal_red }) ++
        builder.fillRectangles(3, .flat, 0) ++
        builder.rectangle(6, 10, 38, 12) ++
        builder.rectangle(6, 24, 12, 14) ++
        builder.rectangle(20, 24, 24, 14) ++
        builder.fillPath(1, .flat, 1) ++
        builder.uint(11) ++
        builder.point(26, 32) ++
        builder.path.horiz(32) ++
        builder.path.vert(26) ++
        builder.path.horiz(36) ++
        builder.path.vert(32) ++
        builder.path.horiz(42) ++
        builder.path.vert(36) ++
        builder.path.horiz(36) ++
        builder.path.vert(42) ++
        builder.path.horiz(32) ++
        builder.path.vert(36) ++
        builder.path.horiz(26) ++
        builder.end_of_document;
};

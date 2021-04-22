const tvg = @import("tvg");

const builder = tvg.builder(.@"1/256");

const dim_black = tvg.Color.fromString("12181d") catch unreachable;
const signal_red = tvg.Color.fromString("910002") catch unreachable;

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
        builder.fillPath(11, .flat, 1) ++
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

const std = @import("std");

const Builder = std.build.Builder;

const LibDunstblick = @import("../libdunstblick/build.zig");

pub fn createExe(b: *Builder, comptime prefix: []const u8) !*std.build.LibExeObjStep {
    return exe;
}

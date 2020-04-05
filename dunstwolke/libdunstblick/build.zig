const std = @import("std");
const Builder = std.build.Builder;

pub fn createLib(b: *Builder, comptime prefix: []const u8) *std.build.LibExeObjStep {
    std.debug.assert(prefix.len > 0);

    const lib = b.addStaticLibrary("dunstblick", prefix ++ "/dunstblick.zig");
    lib.addIncludeDir(prefix);
    lib.addIncludeDir(prefix ++ "/../ext/picohash");
    lib.linkLibC();
    return lib;
}

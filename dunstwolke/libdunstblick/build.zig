const std = @import("std");
const Builder = std.build.Builder;

const xqlib_paths_split = 4;
const xqlib_relpaths = [_][]const u8{
    "/src/xception.cpp",
    "/src/xio.cpp",
    "/src/xnet.cpp",
    "/src/xlog.cpp",
    "/include",
    "/extern/optional/tl",
    "/extern/GSL/include",
};

pub fn build(b: *Builder) !void {
    const xqlib_root = if (b.option([]const u8, "xqlib-root", "Root path to the installation of XQlib.")) |opt| opt else {
        @panic("xqlib-root must be set!");
    };

    var xqlib_abspaths: [xqlib_relpaths.len][]const u8 = undefined;
    {
        var i: usize = 0;
        while (i < xqlib_abspaths.len) : (i += 1) {
            xqlib_abspaths[i] = try std.mem.concat(b.allocator, u8, &[_][]const u8{
                xqlib_root,
                xqlib_relpaths[i],
            });
        }
    }

    const mode = b.standardReleaseOptions();
    const lib = b.addSharedLibrary("dunstblick", null, .{
        .major = 1,
        .minor = 0,
    });

    for (xqlib_abspaths[0..xqlib_paths_split]) |path| {
        lib.addCSourceFile(path, &[_][]const u8{
            "-std=c++17",
            "-Wall",
            "-Wextra",
        });
    }

    lib.addCSourceFile("dunstblick.cpp", &[_][]const u8{
        "-std=c++17",
        "-Wall",
        "-Wextra",
        "-DDUNSTBLICK_LIBRARY",
    });

    lib.addCSourceFile("picohash.c", &[_][]const u8{
        "-std=c99",
        "-Wall",
        "-Wextra",
        "-DDUNSTBLICK_LIBRARY",
    });

    for (xqlib_abspaths[xqlib_paths_split..]) |path| {
        lib.addIncludeDir(path);
    }

    lib.addIncludeDir("../ext/concurrentqueue");
    lib.addIncludeDir("../ext/picohash");

    lib.linkLibC();
    lib.linkSystemLibrary("c++");

    lib.setBuildMode(mode);
    lib.install();
}

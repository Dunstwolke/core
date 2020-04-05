const std = @import("std");

const Builder = std.build.Builder;

const LibDunstblick = @import("../libdunstblick/build.zig");

pub fn createExe(b: *Builder, comptime prefix: []const u8) !*std.build.LibExeObjStep {
    const exe = b.addExecutable("mediaserver", prefix ++ "/src/main.zig");
    exe.linkLibC();
    exe.addIncludeDir(prefix ++ "/../../libdunstblick");
    exe.addIncludeDir(prefix ++ "/./bass");
    exe.addLibPath(prefix ++ "/./bass/x86_64");
    exe.linkSystemLibrary("c++");
    exe.linkSystemLibrary("c++abi");
    exe.linkSystemLibrary("bass");
    exe.install();

    const layout_files = [_][]const u8{
        prefix ++ "/layouts/main.dui",
        prefix ++ "/layouts/menu.dui",
        prefix ++ "/layouts/searchlist.dui",
        prefix ++ "/layouts/searchitem.dui",
    };
    inline for (layout_files) |infile| {
        const outfile = try std.mem.dupe(b.allocator, u8, infile);
        outfile[outfile.len - 3] = 'c';

        const step = b.addSystemCommand(&[_][]const u8{
            "/home/felix/build/dunstwolke-Desktop-Debug/dunstblick-compiler/dunstblick-compiler",
            infile,
            "-o",
            outfile,
            "-c",
            prefix ++ "/layouts/server.json",
        });

        exe.step.dependOn(&step.step);
    }

    return exe;
}

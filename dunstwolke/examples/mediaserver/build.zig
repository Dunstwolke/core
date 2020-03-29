const std = @import("std");

const Builder = std.build.Builder;

const layout_files = [_][]const u8{
    "layouts/main.dui",
    "layouts/menu.dui",
    "layouts/searchlist.dui",
    "layouts/searchitem.dui",
};

pub fn build(b: *Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("mediaserver", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.addIncludeDir("../../libdunstblick");
    exe.addIncludeDir("./bass");
    exe.addLibPath("./bass/x86_64");
    exe.addLibPath("../../libdunstblick/zig-cache/lib");
    exe.linkSystemLibrary("c++");
    exe.linkSystemLibrary("c++abi");
    exe.linkSystemLibrary("bass");
    exe.linkSystemLibrary("dunstblick");
    exe.install();

    for (layout_files) |infile| {
        const outfile = try std.mem.dupe(b.allocator, u8, infile);
        outfile[outfile.len - 3] = 'c';

        const step = b.addSystemCommand(&[_][]const u8{
            "/home/felix/build/dunstwolke-Desktop-Debug/dunstblick-compiler/dunstblick-compiler",
            infile,
            "-o",
            outfile,
            "-c",
            "layouts/server.json",
        });

        exe.step.dependOn(&step.step);
    }

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", "/home/felix/build/dunstwolke-Desktop-Debug/libdunstblick/:./bass/x86_64");

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const std = @import("std");

const Builder = std.build.Builder;

const layout_files = [_][]const u8{
    "layouts/main.dui",
    "layouts/menu.dui",
    "layouts/searchlist.dui",
    "layouts/searchitem.dui",
};

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("widget-tester", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.addIncludeDir("../../libdunstblick");
    exe.addLibPath("../../libdunstblick/zig-cache/lib");
    exe.linkSystemLibrary("c++");
    exe.linkSystemLibrary("c++abi");
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

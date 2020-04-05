const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const lib = @import("libdunstblick/build.zig").createLib(b, "./libdunstblick");
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.install();

    const mediaserver = try @import("examples/mediaserver/build.zig").createExe(b, "./examples/mediaserver");
    mediaserver.linkLibrary(lib);
    mediaserver.setTarget(target);
    mediaserver.setBuildMode(mode);
    mediaserver.install();

    const run_cmd = mediaserver.run();
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", "/home/felix/build/dunstwolke-Desktop-Debug/libdunstblick/:examples/mediaserver/bass/x86_64");

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

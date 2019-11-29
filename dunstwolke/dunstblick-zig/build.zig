const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("dunstblick-zig", "src/main.zig");
    exe.setBuildMode(mode);
    exe.install();

    const tst = b.addTest("src/main.zig");

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tst_step = b.step("test", "Test all the source!");
    tst_step.dependOn(&tst.step);
}

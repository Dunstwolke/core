const builtin = @import("builtin");
const std = @import("std");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("dunstnetz", "src/main.zig");
    // exe.setTheTarget(try std.build.Target.parse("x86_64-windows-gnu"));
    exe.setBuildMode(mode);
    exe.install();

    const _test = b.addTest("src/main.zig");

    const run_cmd = exe.run();
    run_cmd.addArg("11:22:33:44:55:66");
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

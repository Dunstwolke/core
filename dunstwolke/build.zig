const std = @import("std");
const Builder = std.build.Builder;

const pkgs = struct {
    const network = std.build.Pkg{
        .name = "network",
        .path = "./ext/zig-network/network.zig",
    };

    const sdl2 = std.build.Pkg{
        .name = "sdl2",
        .path = "./ext/zig-sdl/src/lib.zig",
    };

    const args = std.build.Pkg{
        .name = "args",
        .path = "./ext/zig-args/args.zig",
    };

    const uri = std.build.Pkg{
        .name = "uri",
        .path = "./ext/zig-uri/uri.zig",
    };
};

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const compiler = b.addExecutable("dunstblick-compiler", "./dunstblick-compiler/main.zig");
    compiler.addPackagePath("args", "./ext/zig-args/args.zig");
    compiler.addIncludeDir("./libdunstblick/include");
    compiler.setTarget(target);
    compiler.setBuildMode(mode);
    compiler.install();

    const compiler_test = b.addTest("./dunstblick-compiler/main.zig");

    const lib = b.addStaticLibrary("dunstblick", "./libdunstblick/src/dunstblick.zig");
    lib.addPackage(pkgs.network);
    lib.addIncludeDir("./libdunstblick/include");
    lib.linkLibC();
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.install();

    // mediaserver project
    const mediaserver = b.addExecutable("mediaserver", "./examples/mediaserver/src/main.zig");
    mediaserver.addIncludeDir("./libdunstblick/include");
    mediaserver.addIncludeDir("./examples/mediaserver/bass");
    mediaserver.addLibPath("./examples/mediaserver/bass/x86_64");
    mediaserver.linkSystemLibrary("bass");
    mediaserver.linkLibrary(lib);
    mediaserver.install();

    const layout_files = [_][]const u8{
        "./examples/mediaserver/layouts/main.dui",
        "./examples/mediaserver/layouts/menu.dui",
        "./examples/mediaserver/layouts/searchlist.dui",
        "./examples/mediaserver/layouts/searchitem.dui",
    };
    inline for (layout_files) |infile| {
        const outfile = try std.mem.dupe(b.allocator, u8, infile);
        outfile[outfile.len - 3] = 'c';

        const step = compiler.run();
        step.addArgs(&[_][]const u8{
            infile,
            "-o",
            outfile,
            "-c",
            "./examples/mediaserver/layouts/server.json",
        });
        mediaserver.step.dependOn(&step.step);
    }

    mediaserver.linkLibrary(lib);
    mediaserver.setTarget(target);
    mediaserver.setBuildMode(mode);
    mediaserver.install();

    // calculator example
    const calculator = b.addExecutable("calculator", null);
    calculator.addIncludeDir("./libdunstblick/include");
    calculator.addCSourceFile("examples/calculator/main.c", &[_][]const u8{});
    calculator.linkLibrary(lib);
    calculator.setTarget(target);
    calculator.setBuildMode(mode);
    calculator.install();

    const calculator_headerGen = compiler.run();
    calculator_headerGen.addArgs(&[_][]const u8{
        "./examples/calculator/layout.ui",
        "-o",
        "./examples/calculator/layout.h",
        "-f",
        "header",
        "-c",
        "./examples/calculator/layout.json",
    });
    calculator.step.dependOn(&calculator_headerGen.step);

    // minimal example
    const minimal = b.addExecutable("minimal", null);
    minimal.addIncludeDir("./libdunstblick/include");
    minimal.addCSourceFile("examples/minimal/main.c", &[_][]const u8{});
    minimal.linkLibrary(lib);
    minimal.setTarget(target);
    minimal.setBuildMode(mode);
    minimal.install();

    const display_client = b.addExecutable("dunstblick-display", "./dunstblick-display/main.zig");

    display_client.addPackage(pkgs.network);
    display_client.addPackage(pkgs.args);
    display_client.addPackage(pkgs.sdl2);
    display_client.addPackage(pkgs.uri);

    display_client.linkLibC();
    display_client.linkSystemLibrary("c++");
    display_client.linkSystemLibrary("sdl2");
    display_client.addIncludeDir("./libdunstblick/include");
    display_client.addIncludeDir("./ext/xqlib/include");
    display_client.addIncludeDir("./ext/xqlib/extern/optional/tl");
    display_client.addIncludeDir("./ext/xqlib/extern/GSL/include");
    display_client.addIncludeDir("./ext/stb");
    display_client.defineCMacro("DUNSTBLICK_SERVER");
    display_client.setBuildMode(mode);
    display_client.setTarget(target);
    display_client.install();

    display_client.addCSourceFile("./dunstblick-display/stb-instantiating.c", &[_][]const u8{
        "-std=c99",
    });

    for (display_client_sources) |src| {
        display_client.addCSourceFile(src, &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=undefined",
        });
    }

    for (xqlib_sources) |src| {
        display_client.addCSourceFile(src, &[_][]const u8{
            "-std=c++17",
            "-fno-sanitize=undefined",
        });
    }

    const run_cmd = mediaserver.run();
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", "examples/mediaserver/bass/x86_64");

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Runs all required tests.");
    test_step.dependOn(&compiler_test.step);
}

const display_client_sources = [_][]const u8{
    "./dunstblick-display/api.cpp",
    "./dunstblick-display/enums.cpp",
    "./dunstblick-display/fontcache.cpp",
    "./dunstblick-display/inputstream.cpp",
    "./dunstblick-display/layouts.cpp",
    "./dunstblick-display/localsession.cpp",
    "./dunstblick-display/main.cpp",
    "./dunstblick-display/networksession.cpp",
    "./dunstblick-display/object.cpp",
    "./dunstblick-display/protocol.cpp",
    "./dunstblick-display/rendercontext.cpp",
    "./dunstblick-display/resources.cpp",
    "./dunstblick-display/session.cpp",
    "./dunstblick-display/tcphost.cpp",
    "./dunstblick-display/testhost.cpp",
    "./dunstblick-display/types.cpp",
    "./dunstblick-display/widget.cpp",
    "./dunstblick-display/widget.create.cpp",
    "./dunstblick-display/widgets.cpp",
};

const xqlib_sources = [_][]const u8{
    "./ext/xqlib/src/sdl2++.cpp",
    "./ext/xqlib/src/xio.cpp",
    "./ext/xqlib/src/xlog.cpp",
    "./ext/xqlib/src/xnet.cpp",
    "./ext/xqlib/src/xception.cpp",
    "./ext/xqlib/src/xstd_format.cpp",
};

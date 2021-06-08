const std = @import("std");
const Builder = std.build.Builder;

const pkgs = struct {
    const network = std.build.Pkg{
        .name = "network",
        .path = "./lib/zig-network/network.zig",
    };

    const sdl2 = std.build.Pkg{
        .name = "sdl2",
        .path = "./lib/SDL.zig/src/lib.zig",
    };

    const args = std.build.Pkg{
        .name = "args",
        .path = "./lib/zig-args/args.zig",
    };

    const uri = std.build.Pkg{
        .name = "uri",
        .path = "./lib/zig-uri/uri.zig",
    };

    const painterz = std.build.Pkg{
        .name = "painterz",
        .path = "./lib/painterz/painterz.zig",
    };

    const tvg = std.build.Pkg{
        .name = "tvg",
        .path = "./lib/tvg/src/lib/tvg.zig",
    };

    const meta = std.build.Pkg{
        .name = "zig-meta",
        .path = "./lib/zig-meta/meta.zig",
    };

    const dunstblick_protocol = std.build.Pkg{
        .name = "dunstblick-protocol",
        .path = "./src/dunstblick-protocol/protocol.zig",
        .dependencies = &[_]std.build.Pkg{
            charm,
        },
    };

    const dunstblick_app = std.build.Pkg{
        .name = "dunstblick-app",
        .path = "./src/dunstblick-app/dunstblick.zig",
        .dependencies = &[_]std.build.Pkg{
            dunstblick_protocol,
            network,
        },
    };

    const dunstnetz = std.build.Pkg{
        .name = "dunstnetz",
        .path = "./src/dunstnetz/main.zig",
        .dependencies = &[_]std.build.Pkg{
            network,
        },
    };

    const wasm = std.build.Pkg{
        .name = "wasm",
        .path = "./lib/wazm/src/main.zig",
    };

    const zigimg = std.build.Pkg{
        .name = "zigimg",
        .path = "./lib/zero-graphics/vendor/zigimg/zigimg.zig",
    };

    const zerog = std.build.Pkg{
        .name = "zero-graphics",
        .path = "./lib/zero-graphics/src/zero-graphics.zig",
        .dependencies = &[_]std.build.Pkg{
            zigimg,
        },
    };

    const charm = std.build.Pkg{
        .name = "charm",
        .path = "./lib/zig-charm/src/main.zig",
    };
};

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const compiler = b.addExecutable("dunstblick-compiler", "./src/dunstblick-compiler/main.zig");
    compiler.addPackage(pkgs.args);
    compiler.setTarget(target);
    compiler.setBuildMode(mode);
    compiler.install();

    const compiler_test = b.addTest("./src/dunstblick-compiler/main.zig");

    const lib = b.addStaticLibrary("dunstblick", "./src/libdunstblick/src/c-binding.zig");
    lib.emit_docs = true;
    lib.addPackage(pkgs.dunstblick_app);
    lib.addPackage(pkgs.dunstblick_protocol);
    lib.linkLibC();
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.install();

    // mediaserver project
    const mediaserver = b.addExecutable("mediaserver", "./src/examples/mediaserver/src/main.zig");
    {
        mediaserver.addIncludeDir("./src/libdunstblick/include");
        mediaserver.addIncludeDir("./src/examples/mediaserver/bass");
        mediaserver.addLibPath("./src/examples/mediaserver/bass/x86_64");
        mediaserver.linkSystemLibrary("bass");
        mediaserver.linkLibrary(lib);
        mediaserver.install();

        const layout_files = [_][]const u8{
            "./src/examples/mediaserver/layouts/main.dui",
            "./src/examples/mediaserver/layouts/menu.dui",
            "./src/examples/mediaserver/layouts/searchlist.dui",
            "./src/examples/mediaserver/layouts/searchitem.dui",
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
                "./src/examples/mediaserver/layouts/server.json",
            });
            mediaserver.step.dependOn(&step.step);
        }

        mediaserver.linkLibrary(lib);
        mediaserver.setTarget(target);
        mediaserver.setBuildMode(mode);
        mediaserver.install();
    }

    // calculator example
    const calculator = b.addExecutable("calculator", null);
    calculator.addIncludeDir("./src/libdunstblick/include");
    calculator.addCSourceFile("src/examples/calculator/main.c", &[_][]const u8{});
    calculator.linkLibrary(lib);
    calculator.setTarget(target);
    calculator.setBuildMode(mode);
    calculator.install();

    const calculator_headerGen = compiler.run();
    calculator_headerGen.addArgs(&[_][]const u8{
        "./src/examples/calculator/layout.ui",
        "-o",
        "./src/examples/calculator/layout.h",
        "-f",
        "header",
        "-c",
        "./src/examples/calculator/layout.json",
    });
    calculator.step.dependOn(&calculator_headerGen.step);

    // minimal example
    const minimal = b.addExecutable("minimal", null);
    minimal.addIncludeDir("./src/libdunstblick/include");
    minimal.addCSourceFile("src/examples/minimal/main.c", &[_][]const u8{});
    minimal.linkLibrary(lib);
    minimal.setTarget(target);
    minimal.setBuildMode(mode);
    minimal.install();

    const display_client = b.addExecutable("dunstblick-display", "./src/dunstblick-display/main.zig");
    {
        display_client.addPackage(pkgs.dunstblick_protocol);
        display_client.addPackage(pkgs.network);
        display_client.addPackage(pkgs.args);
        display_client.addPackage(pkgs.sdl2);
        display_client.addPackage(pkgs.uri);
        display_client.addPackage(pkgs.painterz);

        display_client.linkLibC();
        display_client.linkSystemLibrary("c++");
        display_client.linkSystemLibrary("sdl2");
        display_client.addIncludeDir("./lib/stb");

        display_client.addIncludeDir("./src/libdunstblick/include");
        display_client.addIncludeDir("./lib/xqlib-stripped/include");
        display_client.addIncludeDir("./lib/optional/include/tl");
        display_client.defineCMacro("DUNSTBLICK_SERVER");
        display_client.setBuildMode(mode);
        display_client.setTarget(target);
        display_client.install();

        display_client.addCSourceFile("./src/dunstblick-display/cpp/stb-instantiating.c", &[_][]const u8{
            "-std=c99",
            "-fno-sanitize=undefined",
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

        const layout_files = [_][]const u8{
            "./src/dunstblick-display/layouts/discovery-menu.dui",
            "./src/dunstblick-display/layouts/discovery-list-item.dui",
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
                "./src/dunstblick-display/layouts/resources.json",
            });
            display_client.step.dependOn(&step.step);
        }
    }

    const desktop_app = b.addExecutable("dunstblick-desktop", "src/dunstblick-desktop/main.zig");
    {
        desktop_app.setBuildMode(mode);
        desktop_app.setTarget(target);

        desktop_app.addPackage(pkgs.dunstblick_protocol);
        desktop_app.addPackage(pkgs.network);
        //desktop_app.addPackage(pkgs.args);
        //desktop_app.addPackage(pkgs.uri);
        desktop_app.addPackage(pkgs.tvg);
        desktop_app.addPackage(pkgs.painterz);
        desktop_app.addPackage(pkgs.zerog);
        //desktop_app.addPackage(pkgs.meta);

        // TTF rendering library:
        desktop_app.addIncludeDir("./lib/stb");

        desktop_app.addCSourceFile("lib/zero-graphics/src/rendering/stb_truetype.c", &[_][]const u8{
            "-std=c99",
        });

        const RenderBackend = enum { sdl2, dri };
        const backend = b.option(RenderBackend, "render-backend", "The rendering backend for Dunstblick Desktop") orelse RenderBackend.sdl2;

        desktop_app.addBuildOption(RenderBackend, "render_backend", backend);

        switch (backend) {
            .sdl2 => {
                desktop_app.linkLibC();
                desktop_app.linkSystemLibrary("sdl2");
                desktop_app.addPackage(pkgs.sdl2);
            },
            .dri => {
                @panic("Unsupported build option!");
            },
        }
    }
    desktop_app.install();

    const dunstnetz_daemon = b.addExecutable("dunstnetz-daemon", "src/dunstnetz-daemon/main.zig");
    dunstnetz_daemon.addPackage(pkgs.args);
    dunstnetz_daemon.addPackage(pkgs.dunstnetz);
    dunstnetz_daemon.addPackage(pkgs.wasm);
    // dunstnetz_daemon.install();

    const dunstblick_desktop_test = b.addTest("src/dunstblick-desktop/main.zig");
    {
        dunstblick_desktop_test.addPackage(pkgs.dunstblick_protocol);
        dunstblick_desktop_test.addPackage(pkgs.network);
        dunstblick_desktop_test.addPackage(pkgs.args);
        dunstblick_desktop_test.addPackage(pkgs.sdl2);
        dunstblick_desktop_test.addPackage(pkgs.uri);
        dunstblick_desktop_test.addPackage(pkgs.painterz);
        dunstblick_desktop_test.addPackage(pkgs.meta);
        dunstblick_desktop_test.addPackage(pkgs.zerog);
    }

    const dunstnetz_test = b.addTest("src/dunstnetz/main.zig");
    {
        dunstnetz_test.addPackage(pkgs.network);
    }

    const dunstnetz_daemon_test = b.addTest("src/dunstnetz-daemon/main.zig");
    {
        dunstnetz_daemon_test.addPackage(pkgs.args);
        dunstnetz_daemon_test.addPackage(pkgs.dunstnetz);
        dunstnetz_daemon_test.addPackage(pkgs.wasm);
    }

    const dunstblick_protocol_test = b.addTest(pkgs.dunstblick_protocol.path);
    {
        dunstblick_protocol_test.addPackage(pkgs.charm);
    }

    const run_cmd = display_client.run();
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", "./src/examples/mediaserver/bass/x86_64");

    const install2_step = b.step("install-2", "Installs the new revision of the code. Highly experimental and might break the compiler.");
    install2_step.dependOn(&dunstnetz_daemon.step);
    install2_step.dependOn(&desktop_app.step);

    const run_step = b.step("run", "Run the display client");
    run_step.dependOn(&run_cmd.step);

    const desktop_cmd = desktop_app.run();

    desktop_cmd.step.dependOn(&desktop_app.install_step.?.step);

    const run_desktop_step = b.step("run-desktop", "Run the Dunstblick Desktop");
    run_desktop_step.dependOn(&desktop_cmd.step);

    const run_daemon_step = b.step("run-daemon", "Run the new version of the display client");
    run_daemon_step.dependOn(&dunstnetz_daemon.run().step);

    const test_step = b.step("test", "Runs all required tests.");
    test_step.dependOn(&compiler_test.step);
    test_step.dependOn(&dunstblick_desktop_test.step);
    test_step.dependOn(&dunstnetz_test.step);
    test_step.dependOn(&dunstnetz_daemon_test.step);
    test_step.dependOn(&dunstblick_protocol_test.step);
}

const display_client_sources = [_][]const u8{
    "./src/dunstblick-display/cpp/enums.cpp",
    "./src/dunstblick-display/cpp/inputstream.cpp",
    "./src/dunstblick-display/cpp/layouts.cpp",
    "./src/dunstblick-display/cpp/main.cpp",
    "./src/dunstblick-display/cpp/object.cpp",
    "./src/dunstblick-display/cpp/rendercontext.cpp",
    "./src/dunstblick-display/cpp/resources.cpp",
    "./src/dunstblick-display/cpp/session.cpp",
    "./src/dunstblick-display/cpp/types.cpp",
    "./src/dunstblick-display/cpp/widget.cpp",
    "./src/dunstblick-display/cpp/widget.create.cpp",
    "./src/dunstblick-display/cpp/widgets.cpp",
    "./src/dunstblick-display/cpp/zigsession.cpp",
};

const xqlib_sources = [_][]const u8{
    "./lib/xqlib-stripped/src/xlog.cpp",
};

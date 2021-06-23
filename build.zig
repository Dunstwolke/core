const std = @import("std");
const Builder = std.build.Builder;

const DunstblickSdk = @import("Sdk.zig");

const AndroidSdk = @import("lib/zero-graphics/vendor/ZigAndroidTemplate/Sdk.zig");

const pkgs = struct {
    const network = std.build.Pkg{
        .name = "network",
        .path = .{ .path = "./lib/zig-network/network.zig" },
    };

    const known_folders = std.build.Pkg{
        .name = "known-folders",
        .path = .{ .path = "./lib/known-folders/known-folders.zig" },
    };

    const sdl2 = std.build.Pkg{
        .name = "sdl2",
        .path = .{ .path = "./lib/SDL.zig/src/lib.zig" },
    };

    const args = std.build.Pkg{
        .name = "args",
        .path = .{ .path = "./lib/zig-args/args.zig" },
    };

    const uri = std.build.Pkg{
        .name = "uri",
        .path = .{ .path = "./lib/zig-uri/uri.zig" },
    };

    const painterz = std.build.Pkg{
        .name = "painterz",
        .path = .{ .path = "./lib/painterz/painterz.zig" },
    };

    const tvg = std.build.Pkg{
        .name = "tvg",
        .path = .{ .path = "./lib/tvg/src/lib/tvg.zig" },
    };

    const meta = std.build.Pkg{
        .name = "zig-meta",
        .path = .{ .path = "./lib/zig-meta/meta.zig" },
    };

    const dunstblick_protocol = std.build.Pkg{
        .name = "dunstblick-protocol",
        .path = .{ .path = "./src/dunstblick-protocol/protocol.zig" },
        .dependencies = &[_]std.build.Pkg{
            charm,
        },
    };

    const dunstblick_app = std.build.Pkg{
        .name = "dunstblick-app",
        .path = .{ .path = "./src/dunstblick-app/dunstblick.zig" },
        .dependencies = &[_]std.build.Pkg{
            dunstblick_protocol,
            network,
        },
    };

    const dunstnetz = std.build.Pkg{
        .name = "dunstnetz",
        .path = .{ .path = "./src/dunstnetz/main.zig" },
        .dependencies = &[_]std.build.Pkg{
            network,
        },
    };

    const wasm = std.build.Pkg{
        .name = "wasm",
        .path = .{ .path = "./lib/wazm/src/main.zig" },
    };

    const zigimg = std.build.Pkg{
        .name = "zigimg",
        .path = .{ .path = "./lib/zero-graphics/vendor/zigimg/zigimg.zig" },
    };

    const zerog = std.build.Pkg{
        .name = "zero-graphics",
        .path = .{ .path = "./lib/zero-graphics/src/zero-graphics.zig" },
        .dependencies = &[_]std.build.Pkg{
            zigimg,
        },
    };

    const charm = std.build.Pkg{
        .name = "charm",
        .path = .{ .path = "./lib/zig-charm/src/main.zig" },
    };
};

pub fn build(b: *Builder) !void {
    const sdk = DunstblickSdk.init(b);

    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const compiler = b.addExecutable("dunstblick-compiler", "./src/dunstblick-compiler/main.zig");
    compiler.addPackage(pkgs.args);
    compiler.addPackage(pkgs.dunstblick_protocol);
    compiler.setTarget(target);
    compiler.setBuildMode(mode);
    compiler.install();

    const compiler_test = b.addTest("./src/dunstblick-compiler/main.zig");

    // mediaserver project
    const mediaserver = b.addExecutable("mediaserver", "./src/examples/mediaserver/src/main.zig");
    {
        mediaserver.setBuildMode(mode);
        mediaserver.setTarget(target);

        mediaserver.addPackage(sdk.getAppPackage("dunstblick"));

        // link libbass
        mediaserver.linkLibC();
        mediaserver.addLibPath("./src/examples/mediaserver/bass/x86_64");
        mediaserver.addIncludeDir("./src/examples/mediaserver/bass");
        mediaserver.linkSystemLibrary("bass");

        mediaserver.install();

        {
            const resources = sdk.addBundleResources();

            resources.addLayout("main", .{ .path = "./src/examples/mediaserver/layouts/main.ui" });
            resources.addLayout("menu", .{ .path = "./src/examples/mediaserver/layouts/menu.ui" });
            resources.addLayout("searchlist", .{ .path = "./src/examples/mediaserver/layouts/searchlist.ui" });
            resources.addLayout("searchitem", .{ .path = "./src/examples/mediaserver/layouts/searchitem.ui" });

            resources.addBitmap("icon-volume-off", .{ .path = "./src/examples/mediaserver/resources/volume-off.png" });
            resources.addBitmap("icon-volume-low", .{ .path = "./src/examples/mediaserver/resources/volume-low.png" });
            resources.addBitmap("icon-volume-medium", .{ .path = "./src/examples/mediaserver/resources/volume-medium.png" });
            resources.addBitmap("icon-volume-high", .{ .path = "./src/examples/mediaserver/resources/volume-high.png" });
            resources.addBitmap("icon-skip-next", .{ .path = "./src/examples/mediaserver/resources/skip-next.png" });
            resources.addBitmap("icon-skip-previous", .{ .path = "./src/examples/mediaserver/resources/skip-previous.png" });
            resources.addBitmap("icon-shuffle", .{ .path = "./src/examples/mediaserver/resources/shuffle.png" });
            resources.addBitmap("icon-play", .{ .path = "./src/examples/mediaserver/resources/play.png" });
            resources.addBitmap("icon-menu", .{ .path = "./src/examples/mediaserver/resources/menu.png" });
            resources.addBitmap("icon-album", .{ .path = "./src/examples/mediaserver/resources/album.png" });
            resources.addBitmap("icon-open-folder", .{ .path = "./src/examples/mediaserver/resources/folder-open.png" });
            resources.addBitmap("icon-playlist", .{ .path = "./src/examples/mediaserver/resources/playlist-music.png" });
            resources.addBitmap("icon-radio", .{ .path = "./src/examples/mediaserver/resources/radio.png" });
            resources.addBitmap("icon-repeat-all", .{ .path = "./src/examples/mediaserver/resources/repeat.png" });
            resources.addBitmap("icon-repeat-one", .{ .path = "./src/examples/mediaserver/resources/repeat-once.png" });
            resources.addBitmap("wallpaper", .{ .path = "./src/examples/mediaserver/resources/wallpaper.png" });
            resources.addBitmap("icon-add", .{ .path = "./src/examples/mediaserver/resources/add.png" });
            resources.addBitmap("icon-settings", .{ .path = "./src/examples/mediaserver/resources/settings.png" });
            resources.addBitmap("icon-close", .{ .path = "./src/examples/mediaserver/resources/close.png" });
            resources.addBitmap("album_placeholder", .{ .path = "./src/examples/mediaserver/resources/placeholder.png" });

            resources.addObject("root");

            mediaserver.addPackage(resources.getPackage("app-data"));
        }
    }

    const step = b.step("c-api", "Compiles libdunstblick as well as the C examples");
    {
        // libdunstblick, a C frontend for dunstblick application
        const lib = b.addStaticLibrary("dunstblick", "./src/libdunstblick/src/c-binding.zig");
        lib.emit_docs = true;
        lib.addPackage(pkgs.dunstblick_app);
        lib.addPackage(pkgs.dunstblick_protocol);
        lib.linkLibC();
        lib.setTarget(target);
        lib.setBuildMode(mode);

        // calculator example
        const calculator = b.addExecutable("calculator", null);
        calculator.addIncludeDir("./src/libdunstblick/include");
        calculator.addCSourceFile("src/examples/calculator/main.c", &[_][]const u8{});
        calculator.linkLibrary(lib);
        calculator.setTarget(target);
        calculator.setBuildMode(mode);

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

        step.dependOn(&b.addInstallArtifact(lib).step);
        step.dependOn(&b.addInstallArtifact(calculator).step);
        step.dependOn(&b.addInstallArtifact(minimal).step);
    }

    const dummy_application = b.addExecutable("dummy-application", "src/test/dummy-application.zig");
    dummy_application.addPackage(pkgs.dunstblick_protocol);
    dummy_application.addPackage(pkgs.network);
    dummy_application.setTarget(target);
    dummy_application.setBuildMode(mode);
    dummy_application.install();

    const desktop_app = b.addExecutable("dunstblick-desktop", "src/dunstblick-desktop/main.zig");
    {
        desktop_app.setBuildMode(mode);
        desktop_app.setTarget(target);

        desktop_app.addPackage(pkgs.dunstblick_protocol);
        desktop_app.addPackage(pkgs.network);
        desktop_app.addPackage(pkgs.tvg);
        // desktop_app.addPackage(pkgs.painterz);
        desktop_app.addPackage(pkgs.zerog);
        desktop_app.addPackage(pkgs.known_folders);

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

    // Create App:
    if (b.option(bool, "enable-android", "Enables the Android build options as they have additional system dependencies") orelse false) {
        const key_store = AndroidSdk.KeyStore{
            .file = "zig-cache/key.store",
            .password = "123456",
            .alias = "development_key",
        };

        const sdk_version = AndroidSdk.ToolchainVersions{};

        const android_sdk = AndroidSdk.init(b, null, sdk_version);

        const init_keystore = android_sdk.initKeystore(key_store, .{});

        const keystore_step = b.step("init-keystore", "Initializes a new keystore for development");
        keystore_step.dependOn(init_keystore);

        const app_config = AndroidSdk.AppConfig{
            .display_name = "Dunstblick",
            .app_name = "dunstblick",
            .package_name = "net.random_projects.dunstblick",
            .resources = &[_]AndroidSdk.Resource{
                .{ .path = "mipmap/icon.png", .content = .{ .path = "design/square-logo.png" } },
            },
            .fullscreen = true,
            .permissions = &[_][]const u8{
                "android.permission.INTERNET",
                "android.permission.ACCESS_NETWORK_STATE",
            },
        };

        const app = android_sdk.createApp(
            "zig-out/dunstblick.apk",
            "src/dunstblick-desktop/main.zig",
            app_config,
            mode,
            .{
                .aarch64 = true,
                .x86_64 = true,
                .arm = false,
                .x86 = false,
            },
            key_store,
        );

        const android_pkg = app.getAndroidPackage("android");

        const zero_graphics_with_android = std.build.Pkg{
            .name = "zero-graphics",
            .path = .{ .path = "./lib/zero-graphics/src/zero-graphics.zig" },
            .dependencies = &[_]std.build.Pkg{ pkgs.zigimg, android_pkg },
        };

        for (app.libraries) |app_lib| {
            app_lib.addPackage(pkgs.dunstblick_protocol);
            app_lib.addPackage(pkgs.network);
            app_lib.addPackage(pkgs.tvg);
            app_lib.addPackage(zero_graphics_with_android);
            app_lib.addPackage(pkgs.known_folders);
            app_lib.addPackage(android_pkg);

            // TTF rendering library:
            app_lib.addIncludeDir("./lib/stb");
            app_lib.addCSourceFile("lib/zero-graphics/src/rendering/stb_truetype.c", &[_][]const u8{
                "-std=c99",
            });
        }

        const push_app = app.install();

        const run_app = app.run();
        run_app.dependOn(push_app);

        const app_step = b.step("app", "Compiles the Android app");
        app_step.dependOn(app.final_step);

        const push_step = b.step("push-app", "Compiles the Android app");
        push_step.dependOn(push_app);

        const run_step = b.step("run-app", "Compiles the Android app");
        run_step.dependOn(run_app);
    }

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

    const dunstblick_protocol_test = b.addTest(pkgs.dunstblick_protocol.path.path);
    {
        dunstblick_protocol_test.addPackage(pkgs.charm);
    }

    const install2_step = b.step("build-experimental", "Builds the highly experimental software parts");
    install2_step.dependOn(&dunstnetz_daemon.step);

    const desktop_cmd = desktop_app.run();
    desktop_cmd.step.dependOn(&desktop_app.install_step.?.step);

    const run_desktop_step = b.step("run-desktop", "Run the Dunstblick Desktop");
    run_desktop_step.dependOn(&desktop_cmd.step);

    const run_daemon_step = b.step("run-daemon", "Run the network broker");
    run_daemon_step.dependOn(&dunstnetz_daemon.run().step);

    const test_step = b.step("test", "Runs the full Dunstwolke test suite");
    test_step.dependOn(&compiler_test.step);
    test_step.dependOn(&dunstblick_desktop_test.step);
    test_step.dependOn(&dunstnetz_test.step);
    test_step.dependOn(&dunstnetz_daemon_test.step);
    test_step.dependOn(&dunstblick_protocol_test.step);
}

// const run_cmd = display_client.run();
// run_cmd.step.dependOn(b.getInstallStep());
// run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", "./src/examples/mediaserver/bass/x86_64");

// const run_step = b.step("run", "Run the display client");
// run_step.dependOn(&run_cmd.step);

// const display_client = b.addExecutable("dunstblick-display", "./src/dunstblick-display/main.zig");
// {
//     display_client.addPackage(pkgs.dunstblick_protocol);
//     display_client.addPackage(pkgs.network);
//     display_client.addPackage(pkgs.args);
//     display_client.addPackage(pkgs.sdl2);
//     display_client.addPackage(pkgs.uri);
//     display_client.addPackage(pkgs.painterz);

//     display_client.linkLibC();
//     display_client.linkSystemLibrary("c++");
//     display_client.linkSystemLibrary("sdl2");
//     display_client.addIncludeDir("./lib/stb");

//     display_client.addIncludeDir("./src/libdunstblick/include");
//     display_client.addIncludeDir("./lib/xqlib-stripped/include");
//     display_client.addIncludeDir("./lib/optional/include/tl");
//     display_client.defineCMacro("DUNSTBLICK_SERVER");
//     display_client.setBuildMode(mode);
//     display_client.setTarget(target);
//     display_client.install();

//     display_client.addCSourceFile("./src/dunstblick-display/cpp/stb-instantiating.c", &[_][]const u8{
//         "-std=c99",
//         "-fno-sanitize=undefined",
//     });

//     for (display_client_sources) |src| {
//         display_client.addCSourceFile(src, &[_][]const u8{
//             "-std=c++17",
//             "-fno-sanitize=undefined",
//         });
//     }

//     for (xqlib_sources) |src| {
//         display_client.addCSourceFile(src, &[_][]const u8{
//             "-std=c++17",
//             "-fno-sanitize=undefined",
//         });
//     }

//     const layout_files = [_][]const u8{
//         "./src/dunstblick-display/layouts/discovery-menu.dui",
//         "./src/dunstblick-display/layouts/discovery-list-item.dui",
//     };
//     inline for (layout_files) |infile| {
//         const outfile = try std.mem.dupe(b.allocator, u8, infile);
//         outfile[outfile.len - 3] = 'c';

//         const step = compiler.run();
//         step.addArgs(&[_][]const u8{
//             infile,
//             "-o",
//             outfile,
//             "-c",
//             "./src/dunstblick-display/layouts/resources.json",
//         });
//         display_client.step.dependOn(&step.step);
//     }
// }

// const display_client_sources = [_][]const u8{
//     "./src/dunstblick-display/cpp/enums.cpp",
//     "./src/dunstblick-display/cpp/inputstream.cpp",
//     "./src/dunstblick-display/cpp/layouts.cpp",
//     "./src/dunstblick-display/cpp/main.cpp",
//     "./src/dunstblick-display/cpp/object.cpp",
//     "./src/dunstblick-display/cpp/rendercontext.cpp",
//     "./src/dunstblick-display/cpp/resources.cpp",
//     "./src/dunstblick-display/cpp/session.cpp",
//     "./src/dunstblick-display/cpp/types.cpp",
//     "./src/dunstblick-display/cpp/widget.cpp",
//     "./src/dunstblick-display/cpp/widget.create.cpp",
//     "./src/dunstblick-display/cpp/widgets.cpp",
//     "./src/dunstblick-display/cpp/zigsession.cpp",
// };

// const xqlib_sources = [_][]const u8{
//     "./lib/xqlib-stripped/src/xlog.cpp",
// };

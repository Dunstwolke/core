const std = @import("std");
const Builder = std.build.Builder;

const DunstblickSdk = @import("Sdk.zig");

const ZeroGraphicsSdk = @import("vendor/zero-graphics/Sdk.zig");
const SdlSdk = @import("vendor/zero-graphics/vendor/SDL.zig/Sdk.zig");
const AndroidSdk = @import("vendor/zero-graphics/vendor/ZigAndroidTemplate/Sdk.zig");

const pkgs = struct {
    const network = std.build.Pkg{
        .name = "network",
        .path = .{ .path = "./vendor/zig-network/network.zig" },
    };

    const antiphony = std.build.Pkg{
        .name = "antiphony",
        .path = .{ .path = "vendor/antiphony/src/antiphony.zig" },
        .dependencies = &.{
            .{
                .name = "s2s",
                .path = .{ .path = "vendor/antiphony/vendor/s2s/s2s.zig" },
            },
        },
    };

    const known_folders = std.build.Pkg{
        .name = "known-folders",
        .path = .{ .path = "./vendor/known-folders/known-folders.zig" },
    };

    const args = std.build.Pkg{
        .name = "args",
        .path = .{ .path = "./vendor/zig-args/args.zig" },
    };

    const uri = std.build.Pkg{
        .name = "uri",
        .path = .{ .path = "./vendor/zig-uri/uri.zig" },
    };

    const painterz = std.build.Pkg{
        .name = "painterz",
        .path = .{ .path = "./vendor/painterz/painterz.zig" },
    };

    const tvg = std.build.Pkg{
        .name = "tvg",
        .path = .{ .path = "./vendor/tvg/src/lib/tinyvg.zig" },
    };

    const meta = std.build.Pkg{
        .name = "zig-meta",
        .path = .{ .path = "./vendor/zig-meta/meta.zig" },
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

    const zigimg = std.build.Pkg{
        .name = "zigimg",
        .path = .{ .path = "./vendor/zero-graphics/vendor/zigimg/zigimg.zig" },
    };

    const zerog = std.build.Pkg{
        .name = "zero-graphics",
        .path = .{ .path = "./vendor/zero-graphics/src/zero-graphics.zig" },
        .dependencies = &[_]std.build.Pkg{
            zigimg,
        },
    };

    const charm = std.build.Pkg{
        .name = "charm",
        .path = .{ .path = "./vendor/zig-charm/src/main.zig" },
    };

    const sqlite3 = std.build.Pkg{
        .name = "sqlite3",
        .path = .{ .path = "./vendor/zig-sqlite/sqlite.zig" },
    };

    const uuid6 = std.build.Pkg{
        .name = "uuid6",
        .path = .{ .path = "./vendor/uuid6-zig/src/Uuid.zig" },
    };

    const qoi = std.build.Pkg{
        .name = "qoi",
        .path = .{ .path = "vendor/qoi/src/qoi.zig" },
    };
};

pub fn build(b: *Builder) !void {
    const enable_android = b.option(bool, "enable-android", "Enables the Android build options as they have additional system dependencies") orelse false;

    const sdk = DunstblickSdk.init(b);

    const z3d_sdk = ZeroGraphicsSdk.init(b, enable_android);

    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const musl_target = blk: {
        var copy = target;
        copy.abi = .musl;
        break :blk copy;
    };

    const dunstctl = b.addExecutable("dunstctl", "src/dunstinit/control-main.zig");
    dunstctl.addPackage(pkgs.args);
    dunstctl.addPackage(pkgs.network);
    dunstctl.addPackage(pkgs.antiphony);
    dunstctl.setTarget(target);
    dunstctl.setBuildMode(mode);
    dunstctl.install();

    const dunstinit = b.addExecutable("dunstinit", "src/dunstinit/service-main.zig");
    dunstinit.addPackage(pkgs.args);
    dunstinit.addPackage(pkgs.network);
    dunstinit.addPackage(pkgs.antiphony);
    dunstinit.setTarget(target);
    dunstinit.setBuildMode(mode);
    dunstinit.install();

    const dunstblick_step = b.step("dunstblick", "Makes everything related to dunstblick.");

    const libsqlite3 = b.addStaticLibrary("sqlite3", null);
    libsqlite3.addCSourceFile("./vendor/zig-sqlite/c/sqlite3.c", &[_][]const u8{"-std=c99"});
    libsqlite3.setBuildMode(mode);
    libsqlite3.setTarget(musl_target);
    libsqlite3.linkLibC();

    const libmagic = b.addStaticLibrary("magic", null);
    libmagic.addCSourceFiles(&libmagic_sources, &[_][]const u8{ "-std=c99", "-fno-sanitize=undefined" });
    libmagic.setBuildMode(mode);
    libmagic.setTarget(musl_target);
    libmagic.defineCMacro("HAVE_STDINT_H", null);
    libmagic.defineCMacro("HAVE_INTTYPES_H", null);
    libmagic.defineCMacro("HAVE_WCHAR_H", null);
    libmagic.defineCMacro("HAVE_WCTYPE_H", null);
    libmagic.defineCMacro("HAVE_CONFIG_H", null);
    if (!musl_target.isWindows()) {
        libmagic.defineCMacro("HAVE_UNISTD_H", null);
    }
    libmagic.addIncludeDir("vendor/file-5.40");
    libmagic.linkLibC();

    const dunstfs = b.addExecutable("dfs", "./src/dunstfs/main.zig");
    dunstfs.setBuildMode(mode);
    dunstfs.setTarget(musl_target);
    dunstfs.addPackage(pkgs.sqlite3);
    dunstfs.addPackage(pkgs.args);
    dunstfs.addPackage(pkgs.known_folders);
    dunstfs.addPackage(pkgs.uuid6);
    dunstfs.addIncludeDir("./vendor/zig-sqlite/c");
    dunstfs.linkLibrary(libsqlite3);
    dunstfs.linkLibrary(libmagic);
    dunstfs.linkLibC();
    dunstfs.install();

    const compiler = b.addExecutable("dunstblick-compiler", "./src/dunstblick-compiler/main.zig");
    compiler.addPackage(pkgs.args);
    compiler.addPackage(pkgs.dunstblick_protocol);
    compiler.setTarget(target);
    compiler.setBuildMode(mode);
    compiler.install();

    dunstblick_step.dependOn(&compiler.install_step.?.step);

    const compiler_test = b.addTest("./src/dunstblick-compiler/main.zig");

    // mediaserver project
    const mediaserver = b.addExecutable("mediaserver", "./src/examples/mediaserver/src/main.zig");
    {
        mediaserver.setBuildMode(mode);
        mediaserver.setTarget(.{}); // compile native

        mediaserver.addPackage(sdk.getAppPackage("dunstblick"));

        // link libbass
        mediaserver.linkLibC();
        mediaserver.addLibPath("./src/examples/mediaserver/bass/x86_64");
        mediaserver.addIncludeDir("./src/examples/mediaserver/bass");
        mediaserver.linkSystemLibrary("bass");

        mediaserver.install();

        {
            const resources = sdk.addBundleResources();

            resources.addDrawing("app_icon", .{ .path = "src/examples/mediaserver/resources/disc-player.tvg" });

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
        lib.emit_docs = .emit;
        lib.addPackage(pkgs.dunstblick_app);
        lib.addPackage(pkgs.dunstblick_protocol);
        lib.addIncludeDir("./src/libdunstblick/include");
        lib.linkLibC();
        lib.setTarget(target);
        lib.setBuildMode(mode);
        lib.install();

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

        step.dependOn(&b.addInstallArtifact(lib).step);
        step.dependOn(&b.addInstallArtifact(calculator).step);
        step.dependOn(&b.addInstallArtifact(minimal).step);
    }

    // const dummy_application = b.addExecutable("dummy-application", "src/test/dummy-application.zig");
    // dummy_application.addPackage(pkgs.dunstblick_protocol);
    // dummy_application.addPackage(pkgs.network);
    // dummy_application.setTarget(target);
    // dummy_application.setBuildMode(mode);
    // dummy_application.install();

    // dunstblick_step.dependOn(&dummy_application.install_step.?.step);

    const dunstblick_desktop = z3d_sdk.createApplication("dunstblick_desktop", "src/dunstblick-desktop/main.zig");
    dunstblick_desktop.setDisplayName("Dunstblick Desktop");
    dunstblick_desktop.setPackageName("org.dunstwolke.dunstblick.desktop");
    dunstblick_desktop.setIcon("design/square-logo.png");
    dunstblick_desktop.addPermission(.internet);
    dunstblick_desktop.addPermission(.access_network_state);
    dunstblick_desktop.addPermission(.write_external_storage);
    dunstblick_desktop.addPermission(.read_external_storage);

    dunstblick_desktop.addPackage(pkgs.dunstblick_protocol);
    dunstblick_desktop.addPackage(pkgs.network);
    dunstblick_desktop.addPackage(pkgs.tvg);
    dunstblick_desktop.addPackage(pkgs.known_folders);
    dunstblick_desktop.addPackage(pkgs.qoi);
    dunstblick_desktop.setBuildMode(mode);

    const desktop_app = dunstblick_desktop.compileFor(.{ .desktop = target });
    desktop_app.install();

    dunstblick_step.dependOn(&desktop_app.data.desktop.install_step.?.step);

    // Create App:
    if (enable_android) {
        const keystore_step = b.step("init-keystore", "Initializes a new development key store.");
        keystore_step.dependOn(z3d_sdk.initializeKeystore());

        const app = dunstblick_desktop.compileFor(.android);
        app.install();

        const push_app = app.data.android.install();

        const run_app = app.data.android.run();
        run_app.dependOn(push_app);

        const app_step = b.step("app", "Compiles the Android app");
        app_step.dependOn(app.getStep());

        const push_step = b.step("push-app", "Compiles the Android app");
        push_step.dependOn(push_app);

        const run_step = b.step("run-app", "Compiles the Android app");
        run_step.dependOn(run_app);

        dunstblick_step.dependOn(app.data.android.final_step);
    }

    const dunstnetz_daemon = b.addExecutable("dunstnetz-daemon", "src/dunstnetz-daemon/main.zig");
    dunstnetz_daemon.addPackage(pkgs.args);
    dunstnetz_daemon.addPackage(pkgs.dunstnetz);
    // dunstnetz_daemon.install();

    // const dunstblick_desktop_test = b.addTest("src/dunstblick-desktop/main.zig");
    // {
    //     dunstblick_desktop_test.addPackage(pkgs.dunstblick_protocol);
    //     dunstblick_desktop_test.addPackage(pkgs.network);
    //     dunstblick_desktop_test.addPackage(pkgs.args);
    //     dunstblick_desktop_test.addPackage(pkgs.uri);
    //     dunstblick_desktop_test.addPackage(pkgs.painterz);
    //     dunstblick_desktop_test.addPackage(pkgs.meta);
    //     dunstblick_desktop_test.addPackage(pkgs.zerog);
    // }

    const dunstnetz_test = b.addTest("src/dunstnetz/main.zig");
    {
        dunstnetz_test.addPackage(pkgs.network);
    }

    const dunstnetz_daemon_test = b.addTest("src/dunstnetz-daemon/main.zig");
    {
        dunstnetz_daemon_test.addPackage(pkgs.args);
        dunstnetz_daemon_test.addPackage(pkgs.dunstnetz);
    }

    const dunstblick_protocol_test = b.addTest(pkgs.dunstblick_protocol.path.path);
    {
        dunstblick_protocol_test.addPackage(pkgs.charm);
    }

    const widget_tester = b.addExecutable("widget-tester", "src/test/widget-tester/main.zig");
    {
        widget_tester.setBuildMode(mode);
        widget_tester.setTarget(.{}); // compile native
        widget_tester.addPackage(sdk.getAppPackage("dunstblick"));
        widget_tester.install();

        {
            const resources = sdk.addBundleResources();

            resources.addDrawing("app_icon", .{ .path = "src/test/widget-tester/icon.tvg" });
            resources.addDrawing("ziggy.tvg", .{ .path = "src/test/widget-tester/ziggy.tvg" });

            resources.addLayout("index", .{ .path = "src/test/widget-tester/index.ui" });

            resources.addBitmap("go.qoi", .{ .path = "src/test/widget-tester/go.png" });
            resources.addBitmap("4by3.qoi", .{ .path = "src/test/widget-tester/4by3.png" });

            resources.addObject("root");

            resources.addProperty("main-group");
            resources.addProperty("input-group");

            widget_tester.addPackage(resources.getPackage("app-data"));
        }
    }

    const widget_doc_render = b.addExecutable("render-widget-docs", "src/tools/render-widget-docs.zig");
    widget_doc_render.addPackage(pkgs.dunstblick_protocol);
    widget_doc_render.setBuildMode(mode);
    widget_doc_render.setTarget(target);
    widget_doc_render.install();

    const install2_step = b.step("build-experimental", "Builds the highly experimental software parts");
    install2_step.dependOn(&dunstnetz_daemon.step);

    const desktop_cmd = desktop_app.run();
    desktop_cmd.step.dependOn(&desktop_app.data.desktop.install_step.?.step);

    const run_desktop_step = b.step("run-desktop", "Run the Dunstblick Desktop");
    run_desktop_step.dependOn(&desktop_cmd.step);

    const run_daemon_step = b.step("run-daemon", "Run the network broker");
    run_daemon_step.dependOn(&dunstnetz_daemon.run().step);

    const test_step = b.step("test", "Runs the full Dunstwolke test suite");
    test_step.dependOn(&compiler_test.step);
    // test_step.dependOn(&dunstblick_desktop_test.step);
    test_step.dependOn(&dunstnetz_test.step);
    test_step.dependOn(&dunstnetz_daemon_test.step);
    test_step.dependOn(&dunstblick_protocol_test.step);
}

const libmagic_sources = [_][]const u8{
    "vendor/file-5.40/src/buffer.c",
    "vendor/file-5.40/src/apprentice.c",
    "vendor/file-5.40/src/magic.c",
    "vendor/file-5.40/src/softmagic.c",
    "vendor/file-5.40/src/ascmagic.c",
    "vendor/file-5.40/src/encoding.c",
    "vendor/file-5.40/src/compress.c",
    "vendor/file-5.40/src/is_csv.c",
    "vendor/file-5.40/src/is_json.c",
    "vendor/file-5.40/src/is_tar.c",
    "vendor/file-5.40/src/readelf.c",
    "vendor/file-5.40/src/print.c",
    "vendor/file-5.40/src/fsmagic.c",
    "vendor/file-5.40/src/funcs.c",
    "vendor/file-5.40/src/apptype.c",
    "vendor/file-5.40/src/der.c",
    "vendor/file-5.40/src/cdf.c",
    "vendor/file-5.40/src/cdf_time.c",
    "vendor/file-5.40/src/readcdf.c",
    "vendor/file-5.40/src/fmtcheck.c",
};

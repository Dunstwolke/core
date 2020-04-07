const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const compiler_options = [_][]const u8{
        "-DDUNSTBLICK_COMPILER",
        "-std=c++17",
    };

    const gen_compiler_lexer = b.addSystemCommand(&[_][]const u8{
        "flex",
        "--prefix=Layout",
        "--nounistd",
        "--outfile=layout.lexer.cpp",
        "layout.l",
    });
    gen_compiler_lexer.cwd = "./dunstblick-compiler";

    const compiler = b.addExecutable("dunstblick-compiler", null);
    compiler.addIncludeDir("./ext/json/include");
    compiler.addIncludeDir("./ext/flex"); // for FlexLexer.h
    compiler.addIncludeDir("./ext/GSL/include");
    compiler.addIncludeDir("./dunstblick-display");
    compiler.addIncludeDir("./libdunstblick/include");
    compiler.addCSourceFile("./dunstblick-compiler/main.cpp", &compiler_options);
    compiler.addCSourceFile("./dunstblick-display/enums.cpp", &compiler_options);
    compiler.addCSourceFile("./dunstblick-compiler/layoutparser.cpp", &compiler_options);
    compiler.addCSourceFile("./dunstblick-compiler/layout.lexer.cpp", &compiler_options);
    compiler.linkLibC();
    compiler.linkSystemLibrary("c++");
    compiler.setTarget(target);
    compiler.setBuildMode(mode);
    compiler.step.dependOn(&gen_compiler_lexer.step);
    compiler.install();

    const lib = b.addStaticLibrary("dunstblick", "./libdunstblick/src/dunstblick.zig");
    lib.addIncludeDir("./libdunstblick/include");
    lib.addIncludeDir("./ext/picohash");
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

    const run_cmd = mediaserver.run();
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.setEnvironmentVariable("LD_LIBRARY_PATH", "examples/mediaserver/bass/x86_64");

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

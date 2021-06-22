const std = @import("std");
const args_parser = @import("args");

const Compiler = @import("Compiler.zig");
const Database = @import("Database.zig");

const FileType = enum { binary, header };

fn usage(stream: anytype, exe_name: []const u8) !void {
    const name = std.fs.path.basename(exe_name);

    try stream.print("usage: {s} layoutfile\n", .{name});
    try stream.writeAll(
        \\Compiles a dunstblick layout file into the binary representation.
        \\  -h, --help              Shows this text.
        \\  -o, --output [file]     Renders the output into [file].
        \\  -c, --config [file]     Uses [file] as the json config file.
        \\  -u, --update-config     Updates the config file when a unknown identifier is found
        \\  -f, --file-type [type]  Sets the file type to 'binary' or 'header'. 
        \\
    );
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    const args = try args_parser.parseForCurrentProcess(struct {
        // This declares long options for double hyphen
        output: ?[]const u8 = null,
        config: ?[]const u8 = null,
        @"file-type": FileType = .binary,
        @"update-config": bool = false,
        help: bool = false,

        // This declares short-hand options for single hyphen
        pub const shorthands = .{
            .u = "update-config",
            .f = "file-type",
            .c = "config",
            .o = "output",
            .h = "help",
        };
    }, allocator);
    defer args.deinit();

    if (args.options.help) {
        try usage(std.io.getStdOut().writer(), args.executable_name orelse return 1);
        return 0;
    }

    if (args.positionals.len != 1) {
        try usage(std.io.getStdErr().writer(), args.executable_name orelse return 1);
        return 1;
    }

    var database: Database = if (args.options.config) |cfgfile| blk: {
        var buffer = std.fs.cwd().readFileAlloc(allocator, cfgfile, 1 << 20) catch |err| switch (err) { // 1 MB
            error.FileNotFound => |e| if (args.options.@"update-config")
                break :blk Database.init(allocator, true)
            else
                return e,
            else => |e| return e,
        };
        defer allocator.free(buffer);

        break :blk try Database.fromJson(allocator, args.options.@"update-config", buffer);
    } else Database.init(allocator, args.options.@"update-config");
    defer database.deinit();

    const inputFile = args.positionals[0];

    const outfile_path = if (args.options.output) |outfile| outfile else {
        try std.io.getStdOut().writer().writeAll("implicit outfile not supported yet!\n");
        return 1;
    };

    var compiler = Compiler.init(allocator, &database);
    defer compiler.deinit();

    const layout_data = blk: {
        var src_file = std.fs.cwd().openFile(inputFile, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                try std.io.getStdOut().writer().writeAll("could not read the input file!\n");
                return 1;
            },
            else => return err,
        };
        defer src_file.close();

        var data = std.ArrayList(u8).init(allocator);
        defer data.deinit();

        compiler.compile(
            src_file.reader(),
            data.writer(),
        ) catch break :blk null;

        break :blk data.toOwnedSlice();
    };

    defer if (layout_data) |data|
        allocator.free(data);

    const errors = compiler.getErrors();
    if (errors.len > 0) {
        for (errors) |err| {
            std.debug.print("error: {s}\n", .{err});
        }
        return 1;
    }

    if (layout_data) |data| {
        {
            var file = try std.fs.cwd().createFile(outfile_path, .{ .exclusive = false, .read = false });
            defer file.close();

            var stream = file.writer();

            switch (args.options.@"file-type") {
                .binary => try stream.writeAll(data),

                .header => {
                    for (data) |c| {
                        try stream.print("0x{X}, ", .{c});
                    }
                },
            }
        }

        if (args.options.@"update-config") {
            if (args.options.config) |config_file| {
                var file = try std.fs.cwd().createFile(config_file, .{ .exclusive = false, .read = false });
                defer file.close();

                try database.toJson(file.writer());
            }
        }

        return 0;
    } else {
        return 1;
    }
}

test {
    _ = @import("tests.zig");
}

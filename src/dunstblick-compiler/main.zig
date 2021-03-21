const std = @import("std");
const args_parser = @import("args");

const Compiler = @import("Compiler.zig");
const Database = @import("Database.zig");

const FileType = enum { binary, header };

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

        // This declares short-hand options for single hyphen
        pub const shorthands = .{
            .u = "update-config",
            .f = "file-type",
            .c = "config",
            .o = "output",
        };
    }, allocator);
    defer args.deinit();

    switch (args.positionals.len) {
        0 => {
            try std.io.getStdOut().writer().print("usage: {s} [-c config] [-u] [-o output] layoutfile\n", .{
                args.executable_name,
            });
            return 1;
        },
        2 => {
            try std.io.getStdOut().writer().writeAll("invalid number of args!\n");
            return 1;
        },
        else => {},
    }

    var database: Database = if (args.options.config) |cfgfile| blk: {
        var buffer = try std.fs.cwd().readFileAlloc(allocator, cfgfile, 1 << 20); // 1 MB
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
        var file = try std.fs.cwd().createFile(outfile_path, .{ .exclusive = false, .read = false });
        defer file.close();

        var stream = file.writer();

        switch (args.options.@"file-type") {
            .binary => try stream.writeAll(data),

            .header => {
                for (data) |c, i| {
                    try stream.print("0x{X}, ", .{c});
                }
            },
        }
        return 0;
    } else {
        return 1;
    }
}

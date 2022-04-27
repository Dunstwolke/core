//! DunstFS experimental implementation and command line client.
//!
//! Planned features:
//! - Search the DFS
//! - Add files
//! - RMW files (move to temp, open with editor, write back and update checksum)
//!
//!

// TODO:
// - Implement actual tag gobbling instead of SQL filters

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\dfs-daemon [options]
        \\
        \\  -h, --help     Will output this text.
        \\  -v, --verbose  Will output more detailled information about what happens.
        \\      --version  Prints the current version number
        \\
    );
}

const std = @import("std");
const uri = @import("uri");
const builtin = @import("builtin");
const args_parser = @import("args");
const sqlite3 = @import("sqlite3");
const known_folders = @import("known-folders");
const Uuid = @import("uuid6");
const serve = @import("serve");

const logger = std.log.scoped(.dfs);

// Set the log level to warning
pub const log_level: std.log.Level = if (builtin.mode == .Debug) std.log.Level.debug else std.log.Level.info;

// Define root.log to override the std implementation
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@enumToInt(level) > @enumToInt(current_log_level))
        return;
    std.log.defaultLog(level, scope, format, args);
}

var current_log_level: std.log.Level = if (builtin.mode == .Debug) .debug else .warn;

const CommonOptions = struct {
    help: bool = false,
    verbose: bool = false,
    version: bool = false,

    pub const shorthands = .{
        .h = "help",
        .v = "verbose",
    };
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = gpa.allocator();

const version = struct {
    const major = 0;
    const minor = 1;
    const patch = 0;
};

pub fn main() !u8 {
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(global_allocator);
    defer arena.deinit();

    var img_dir = try std.fs.cwd().openDir("src/dunstfs/html/img", .{});
    defer img_dir.close();

    var cli = args_parser.parseForCurrentProcess(CommonOptions, global_allocator, .print) catch return 1;
    defer cli.deinit();

    var stdout_raw = std.io.getStdOut().writer();

    var buffered_stdout = std.io.bufferedWriter(stdout_raw);
    defer buffered_stdout.flush() catch {}; // well, we can't do anything anymore here anyways

    var stdout = buffered_stdout.writer();

    // Do opt early out when invoking help command, as we don't need to initialize anything here.
    if (cli.options.help) {
        try printUsage(stdout);
        return 0;
    }

    if (cli.options.version) {
        try stdout.print("DunstFS {}.{}.{}\n", .{ version.major, version.minor, version.patch });
        return 0;
    }

    if (cli.options.verbose)
        current_log_level = .info;

    var http_server = try serve.HttpListener.init(global_allocator);
    defer http_server.deinit();

    try http_server.addEndpoint(serve.IP.any_v4, 8444);

    try http_server.start();

    std.log.info("interface ready.", .{});

    while (true) {
        var temp_memory = std.heap.ArenaAllocator.init(global_allocator);
        defer temp_memory.deinit();

        var context = try http_server.getContext();
        defer context.deinit();

        const host_name = context.request.headers.get("Host") orelse @as([]const u8, "this");

        const fake_uri = try std.fmt.allocPrint(temp_memory.allocator(), "http://{s}{s}", .{
            host_name,
            context.request.url,
        });

        const url = uri.parse(fake_uri) catch |err| {
            std.log.err("failed to parse url '{s}': {}", .{ context.request.url, err });
            continue;
        };

        if (std.mem.eql(u8, url.path, "/")) {
            // index page

            const response = try context.response.writer();
            try templates.frame.render(response, IndexView{});
        } else if (std.mem.startsWith(u8, url.path, "/file/")) {
            // file view

            const response = try context.response.writer();
            try templates.frame.render(response, FileView{});
        } else if (std.mem.eql(u8, url.path, "/settings")) {
            // settings page

            const response = try context.response.writer();
            try templates.frame.render(response, SettingsView{});
        } else if (std.mem.eql(u8, url.path, "/style.css")) {
            try context.response.setHeader("Content-Type", "text/css");

            const response = try context.response.writer();
            try response.writeAll(@embedFile("html/style.css"));
        } else if (std.mem.startsWith(u8, url.path, "/img/")) {
            const name = std.fs.path.basename(url.path);

            var file = try img_dir.openFile(name, .{});
            defer file.close();

            try context.response.setHeader("Content-Type", "image/svg+xml"); // TODO: Replace with actual mime type

            const response = try context.response.writer();

            var fifo = std.fifo.LinearFifo(u8, .{ .Static = 4096 }).init();
            try fifo.pump(file.reader(), response);
        } else {
            const response = try context.response.writer();
            try response.print("File not found: {s}", .{url.path});
        }
    }

    return 0;
}

const IndexView = struct {
    const Self = @This();

    pub fn renderContent(self: Self, writer: anytype) !void {
        try templates.index.render(writer, self);
    }
};

const SettingsView = struct {
    const Self = @This();

    pub fn renderContent(self: Self, writer: anytype) !void {
        try templates.settings.render(writer, self);
    }
};

const FileView = struct {
    const Self = @This();

    pub fn renderContent(self: Self, writer: anytype) !void {
        try templates.file.render(writer, self);
    }
};

const templates = struct {
    pub const frame = @import("template.frame");
    pub const index = @import("template.index");
    pub const settings = @import("template.settings");
    pub const file = @import("template.file");
};

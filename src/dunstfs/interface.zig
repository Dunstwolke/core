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
const Uuid = @import("uuid6");
const serve = @import("serve");

const logger = std.log.scoped(.dfs_interface);

const RpcClient = @import("RpcClient.zig");

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
    host: ?[]const u8 = null,

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

    var rpc = RpcClient.connect(gpa.allocator(), cli.options.host) catch |err| {
        logger.err("could not connect to rpc daemon: {s}", .{@errorName(err)});
        return 1;
    };
    defer rpc.deinit();

    var http_server = try serve.HttpListener.init(global_allocator);
    defer http_server.deinit();

    try http_server.addEndpoint(serve.IP{ .ipv4 = .{ 127, 0, 42, 1 } }, 8444);

    try http_server.start();

    std.log.info("interface ready.", .{});

    while (true) {
        var temp_memory = std.heap.ArenaAllocator.init(global_allocator);
        defer temp_memory.deinit();

        var context = try http_server.getContext();
        defer context.deinit();

        handleRequest(context, &rpc, img_dir, temp_memory.allocator()) catch |err| {
            logger.err("failed to handle request to {s}: {s}", .{
                context.request.url,
                @errorName(err),
            });
        };
    }

    return 0;
}

fn handleRequest(context: *serve.HttpContext, rpc: *RpcClient, img_dir: std.fs.Dir, allocator: std.mem.Allocator) !void {
    const host_name = context.request.headers.get("Host") orelse @as([]const u8, "this");

    const fake_uri = try std.fmt.allocPrint(allocator, "http://{s}{s}", .{
        host_name,
        context.request.url,
    });

    const url = uri.parse(fake_uri) catch |err| {
        std.log.err("failed to parse url '{s}': {}", .{ context.request.url, err });
        return;
    };

    var query = std.StringArrayHashMap([]const u8).init(allocator);
    defer query.deinit();

    {
        var iter = std.mem.tokenize(u8, url.query orelse "", "&");
        while (iter.next()) |raw_kvp| {
            if (std.mem.indexOfScalar(u8, raw_kvp, '=')) |split_index| {
                const raw_key = raw_kvp[0..split_index];
                const raw_value = raw_kvp[split_index + 1 ..];

                const key = try uri.unescapeString(allocator, raw_key);
                const value = try uri.unescapeString(allocator, raw_value);

                try query.put(key, value);
            } else {
                const raw_key = raw_kvp;
                const key = try uri.unescapeString(allocator, raw_key);

                try query.put(key, "");
            }
        }
    }

    {
        var iter = query.iterator();
        while (iter.next()) |kvp| {
            std.debug.print("'{}' => '{}'\n", .{
                std.fmt.fmtSliceEscapeUpper(kvp.key_ptr.*),
                std.fmt.fmtSliceEscapeUpper(kvp.value_ptr.*),
            });
        }
    }

    if (std.mem.eql(u8, url.path, "/")) {
        // index page

        var pos_filters = std.ArrayList([]const u8).init(allocator);
        var neg_filters = std.ArrayList([]const u8).init(allocator);

        var search_string_raw = query.get("filter") orelse "";
        var search_string_filt = std.ArrayList(u8).init(allocator);

        {
            var iter = std.mem.tokenize(u8, search_string_raw, " \t\r\n");
            while (iter.next()) |item| {
                if (std.mem.eql(u8, item, "-"))
                    continue;
                if (search_string_filt.items.len > 0) {
                    try search_string_filt.append(' ');
                }
                try search_string_filt.appendSlice(item);

                if (std.mem.startsWith(u8, item, "-")) {
                    try neg_filters.append(item[1..]);
                } else {
                    try pos_filters.append(item);
                }
            }
        }

        var files = try rpc.list(
            allocator,
            0,
            null,
            pos_filters.items,
            neg_filters.items,
        );

        var tags = std.StringArrayHashMap(void).init(allocator);
        defer tags.deinit();

        for (files) |file| {
            const info = try rpc.info(allocator, file.uuid);
            for (info.tags) |tag| {
                try tags.put(tag, {});
            }
        }

        const response = try context.response.writer();
        try templates.frame.render(response, IndexView{
            .files = files,
            .tags = tags.keys(),
            .search_string = search_string_filt.items,
        });
    } else if (std.mem.startsWith(u8, url.path, "/file/")) {
        // file view

        if (Uuid.parse(url.path[6..])) |file_uuid| {
            if (query.contains("raw")) {
                if (rpc.get(allocator, file_uuid, "/tmp/demo_file")) |revision| {
                    try context.response.setHeader("Content-Type", revision.mime);

                    var fifo = std.fifo.LinearFifo(u8, .{ .Static = 8192 }).init();

                    var file = try std.fs.cwd().openFile("/tmp/demo_file", .{});
                    defer file.close();

                    const response = try context.response.writer();

                    try fifo.pump(file.reader(), response);
                } else |err| {
                    try context.response.setHeader("Content-Type", "text/plain");

                    const response = try context.response.writer();
                    try response.print("Could not fetch file content: {s}", .{@errorName(err)});
                }
            } else {
                const file_info = try rpc.info(allocator, file_uuid);

                const response = try context.response.writer();
                try templates.frame.render(response, FileView{
                    .file_uuid = file_uuid,
                    .file_info = file_info,
                });
            }
        } else |_| {
            try context.response.setHeader("Content-Type", "text/plain");
            try context.response.setStatusCode(.bad_request);

            const response = try context.response.writer();
            try response.print("Invalid url: {s}", .{url.path});
        }
    } else if (std.mem.eql(u8, url.path, "/settings")) {
        // settings page

        const response = try context.response.writer();
        try templates.frame.render(response, SettingsView{});
    } else if (std.mem.eql(u8, url.path, "/style.css")) {
        try context.response.setHeader("Content-Type", "text/css");

        const response = try context.response.writer();
        try response.writeAll(@embedFile("html/style.css"));
    } else if (std.mem.startsWith(u8, url.path, "/img/")) {
        const name = url.path[5..];

        var file = img_dir.openFile(name, .{}) catch |err| {
            try context.response.setStatusCode(.not_found);

            const response = try context.response.writer();
            try response.print("could not find file {s}: {s}\n", .{ url.path, @errorName(err) });
            return;
        };
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

pub const ViewFeatures = struct {
    search: bool,
    tags: bool,
    upload: bool,

    pub fn any(v: ViewFeatures) bool {
        return v.search or v.tags or v.upload;
    }
};

const IndexView = struct {
    const Self = @This();

    pub const features = ViewFeatures{
        .search = true,
        .tags = true,
        .upload = true,
    };

    tags: []const []const u8,
    files: []const RpcClient.FileListItem,
    search_string: []const u8,

    pub fn renderContent(self: Self, writer: anytype) !void {
        try templates.index.render(writer, self);
    }

    pub fn getIcon(self: Self, file: RpcClient.FileListItem) []const u8 {
        _ = self;

        // try exact matching
        inline for (comptime std.meta.fields(@TypeOf(mime_icon_table))) |fld| {
            if (std.mem.eql(u8, fld.name, file.mime_type)) {
                return @field(mime_icon_table, fld.name);
            }
        }

        // try class matching:
        if (std.mem.startsWith(u8, file.mime_type, "image/")) {
            return "mime/image.svg";
        }
        if (std.mem.startsWith(u8, file.mime_type, "audio/")) {
            return "mime/music.svg";
        }
        if (std.mem.startsWith(u8, file.mime_type, "text/")) {
            return "mime/document.svg";
        }
        if (std.mem.startsWith(u8, file.mime_type, "video/")) {
            return "mime/video.svg";
        }

        return "mime/generic.svg";
    }

    pub fn getSearch(self: Self) []const u8 {
        return self.search_string;
    }

    pub fn getTags(self: Self) []const []const u8 {
        return self.tags;
    }
};

const mime_icon_table = .{
    .@"application/zip" = "mime/archive.svg",
    .@"application/x-tar" = "mime/archive.svg",
    .@"application/x-7z-compressed" = "mime/archive.svg",

    .@"application/rtf" = "mime/document.svg",
    .@"application/dxf" = "mime/cad.svg",
    .@"application/pdf" = "mime/pdf.svg",

    // microsoft office
    .@"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "mime/ms-excel.svg", // .xlsx
    .@"application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "mime/ms-word.svg", // .docx
    .@"application/vnd.openxmlformats-officedocument.presentationml.presentation" = "mime/ms-powerpoint.svg", // .pptx

    .@"application/msword" = "mime/ms-word.svg", // .doc
    .@"application/mspowerpoint" = "mime/ms-powerpoint.svg", // .ppt
    .@"application/msexcel" = "mime/ms-excel.svg", // .xls

    // libre/open office
    .@"application/vnd.oasis.opendocument.chart" = "mime/chart.svg", //  *.odc
    .@"application/vnd.oasis.opendocument.formula" = "mime/generic.svg", //  *.odf
    .@"application/vnd.oasis.opendocument.graphics" = "mime/cad.svg", //  *.odg
    .@"application/vnd.oasis.opendocument.image" = "mime/image.svg", //  *.odi
    .@"application/vnd.oasis.opendocument.presentation" = "mime/generic.svg", //  *.odp
    .@"application/vnd.oasis.opendocument.spreadsheet" = "mime/chart.svg", //  *.ods
    .@"application/vnd.oasis.opendocument.text" = "mime/document.svg", //  *.odt
    .@"application/vnd.oasis.opendocument.text-master" = "mime/document.svg", //  *.odm

    .@"text/rtf" = "mime/document.svg",
    .@"text/tab-separated-values" = "mime/csv.svg",
    .@"text/csv" = "mime/csv.svg",
    .@"text/xml" = "mime/code.svg",
    .@"text/css" = "mime/code.svg",
    .@"text/html" = "mime/code.svg",
    .@"text/javascript" = "mime/code.svg",
    .@"text/json" = "mime/code.svg",
};

const SettingsView = struct {
    const Self = @This();

    pub const features = ViewFeatures{
        .search = false,
        .tags = false,
        .upload = false,
    };

    pub fn renderContent(self: Self, writer: anytype) !void {
        try templates.settings.render(writer, self);
    }
};

const FileView = struct {
    const Self = @This();

    file_uuid: Uuid,
    file_info: RpcClient.FileInfo,

    pub const features = ViewFeatures{
        .search = false,
        .tags = true,
        .upload = false,
    };

    pub fn renderContent(self: Self, writer: anytype) !void {
        try templates.file.render(writer, self);
    }

    pub fn getTags(self: Self) []const []const u8 {
        return self.file_info.tags;
    }
};

const templates = struct {
    pub const frame = @import("template.frame");
    pub const index = @import("template.index");
    pub const settings = @import("template.settings");
    pub const file = @import("template.file");
};

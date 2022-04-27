const std = @import("std");
const args_parser = @import("args");
const network = @import("network");
const builtin = @import("builtin");
const Uuid = @import("uuid6");
const sqlite3 = @import("sqlite3");
const known_folders = @import("known-folders");

const libmagic = @import("magic.zig");
const MagicSet = libmagic.MagicSet;

const logger = std.log.scoped(.dfs);

const rpc = @import("rpc.zig");

fn printUsage(stream: anytype, exe_name: []const u8) !void {
    _ = exe_name;
    try stream.writeAll(
        \\dfs-daemon [-h] [-e] [-v] [--version]
        \\  -h, --help     Show this help
        \\  -e, --expose   Expose service to public interface
        \\  -v, --verbose  Prints more diagnostics
        \\      --version  Prints version information
        \\
    );
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = gpa.allocator();

const version = struct {
    const major = 0;
    const minor = 1;
    const patch = 0;
};

const RpcHostEndPoint = rpc.Definition.HostEndPoint(network.Socket.Reader, network.Socket.Writer, SystemInterface);

const CliOptions = struct {
    help: bool = false,
    expose: bool = false,
    version: bool = false,
    verbose: bool = false,

    pub const shorthands = .{
        .h = "help",
        .e = "expose",
        .v = "verbose",
    };
};

pub fn main() !u8 {
    defer _ = gpa.deinit();

    var stdout = std.io.getStdOut().writer();
    // var stderr = std.io.getStdErr().writer();

    var cli = args_parser.parseForCurrentProcess(CliOptions, gpa.allocator(), .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        try printUsage(stdout, cli.executable_name.?);
        return 0;
    }

    if (cli.options.version) {
        // if (cli.options.json) {
        //     try stdout.print(
        //         \\{{ "major": {d}, "minor": {d}, "patch": {d} }}
        //         \\
        //     , .{ version.major, version.minor, version.patch });
        // } else {
        try stdout.print("DunstFS Daemon {}.{}.{}\n", .{ version.major, version.minor, version.patch });
        // }
        return 0;
    }

    if (cli.options.verbose) {
        current_log_level = .info;
    }

    logger.info("Open magic database...", .{});
    const magic = try MagicSet.openBuiltin();
    defer magic.close();

    logger.info("Initialize PRNG...", .{});
    var rng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));

    logger.info("Initialize UUID source...", .{});
    const source = Uuid.v4.Source.init(rng.random());

    _ = source;

    logger.info("Determine the data directory...", .{});
    var root_dir: std.fs.Dir = blk: {
        var data_dir = (try known_folders.open(global_allocator, .data, .{})) orelse {
            std.log.err("Missing data directory!\n", .{});
            return 1;
        };
        defer data_dir.close();

        break :blk data_dir.makeOpenPath("dunstwolke/filesystem", .{}) catch {
            std.log.err("Could not open the DunstFS data directory!\n", .{});
            return 1;
        };
    };
    defer root_dir.close();

    logger.info("Create dataset folder...", .{});
    root_dir.makeDir("datasets") catch |err| switch (err) {
        error.PathAlreadyExists => {}, // nice!
        else => |e| return e,
    };

    logger.info("Open dataset folder...", .{});
    var dataset_dir = try root_dir.openDir("datasets", .{});
    defer dataset_dir.close();

    // meh. sqlite needs this (still), though
    try root_dir.setAsCwd();

    if (cli.options.verbose) {
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var path = try std.fs.realpath(".", &buffer);
        logger.info("Data directory is '{s}'", .{path});
    }

    var interface = SystemInterface{
        .allocator = global_allocator,
        .db = undefined,
        .db_intf = undefined,
    };

    logger.info("Opening sqlite3 databse...", .{});
    interface.db = try sqlite3.Db.init(.{
        .mode = .{ .File = "storage.db3" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
    });
    defer interface.db.deinit();

    logger.info("Initialize database...", .{});
    inline for (prepared_statement_sources.init_statements) |code| {
        var init_db_stmt = interface.db.prepareDynamic(code) catch |err| {
            logger.err("error while executing sql:\n{s}", .{code});
            return err;
        };
        defer init_db_stmt.deinit();

        try init_db_stmt.exec(.{}, .{});
    }

    logger.info("Create prepared statements...", .{});

    var diags = sqlite3.Diagnostics{};
    inline for (comptime std.meta.fields(DatabaseInterface)) |fld| {
        @field(interface.db_intf, fld.name) = interface.db.prepareWithDiags(@field(prepared_statement_sources, fld.name), .{
            .diags = &diags,
        }) catch |err| {
            logger.err("failed to initialize db statement: {}, {}", .{
                err,
                diags,
            });
            return 1;
        };
    }

    logger.info("Prepare RPC interface...", .{});

    var listener = try network.Socket.create(.ipv4, .tcp);
    defer listener.close();

    try listener.enablePortReuse(true);

    try listener.bind(if (cli.options.expose)
        rpc.public_end_point
    else
        rpc.end_point);

    try listener.listen();

    logger.info("Starting RPC interface...", .{});

    logger.info("ready.", .{});

    while (true) {
        var client_socket = try listener.accept();
        errdefer client_socket.close();

        var management_thread = try std.Thread.spawn(.{}, processManagementConnectionSafe, .{ client_socket, &interface });
        management_thread.detach();
    }

    return 0;
}

const SystemInterface = struct {
    allocator: std.mem.Allocator,
    global_lock: std.Thread.Mutex = .{},
    db: sqlite3.Db,
    db_intf: DatabaseInterface,

    // pub fn getServiceStatus(service: []const u8) rpc.ServiceControlError!rpc.ServiceStatus {
    //     var cmd = Command{ .getServiceStatus = .{
    //         .service = service,
    //     } };

    //     try command_queue.execute(&cmd, command_timeout);
    //     if (cmd.getServiceStatus.err) |err|
    //         return err;
    //     return cmd.getServiceStatus.result;
    // }

    pub fn lock(self: *SystemInterface) void {
        self.global_lock.lock();
    }

    pub fn unlock(self: *SystemInterface) void {
        self.global_lock.unlock();
    }

    // File management
    pub fn add(source_file: []const u8, mime_type: []const u8, name: ?[]const u8, tags: []const []const u8) rpc.AddFileError!Uuid {
        _ = source_file;
        _ = mime_type;
        _ = name;
        _ = tags;
        @panic("add not implemented yet");
    }
    pub fn update(file: Uuid, source_file: []const u8, mime: []const u8) rpc.UpdateFileError!void {
        _ = file;
        _ = source_file;
        _ = mime;
        @panic("not implemented yet");
    }
    pub fn rename(file: Uuid, name: ?[]const u8) rpc.RenameFileError!void {
        _ = file;
        _ = name;
        @panic("not implemented yet");
    }
    pub fn delete(file: Uuid) rpc.RemoveFileError!void {
        _ = file;
        @panic("not implemented yet");
    }
    pub fn get(file: Uuid, target: []const u8) rpc.GetFileError!void {
        _ = file;
        _ = target;
        @panic("not implemented yet");
    }
    pub fn open(file: Uuid, read_only: bool) rpc.OpenFileError!void {
        _ = file;
        _ = read_only;
        @panic("not implemented yet");
    }
    pub fn info(file: Uuid) rpc.FileInfoError!rpc.FileInfo {
        _ = file;
        @panic("not implemented yet");
    }

    pub fn list(skip: u32, limit: ?u32, include_filters: []const []const u8, exclude_filters: []const []const u8) rpc.ListFilesError!rpc.FileListItem {
        _ = skip;
        _ = limit;
        _ = include_filters;
        _ = exclude_filters;
        @panic("not implemented yet");
    }
    pub fn find(skip: u32, limit: ?u32, filter: []const u8) rpc.ListFilesError!rpc.FileListItem {
        _ = skip;
        _ = limit;
        _ = filter;
        @panic("not implemented yet");
    }

    // Tag management
    pub fn addTags(file: Uuid, tags: []const []const u8) rpc.AddTagError!void {
        _ = file;
        _ = tags;
        @panic("not implemented yet");
    }
    pub fn removeTags(file: Uuid, tags: []const []const u8) rpc.RemoveTagError!void {
        _ = file;
        _ = tags;
        @panic("not implemented yet");
    }
    pub fn listFileTags(file: Uuid) rpc.ListFileTagsError![]const u8 {
        _ = file;
        @panic("not implemented yet");
    }
    pub fn listTags(sys: *SystemInterface, filter: ?[]const u8, limit: ?u32) rpc.ListTagsError![]rpc.TagInfo {
        const real_limit: u32 = limit orelse std.math.maxInt(u32);
        const real_filter = sqlite3.Text{ .data = filter orelse "%" };

        var items = std.ArrayList(rpc.TagInfo).init(sys.allocator);
        defer items.deinit();

        var iter = sys.db_intf.list_tags.iterator(rpc.TagInfo, .{ .filter = real_filter, .limit = real_limit }) catch |err| return switch (err) {
            error.OutOfMemory => |e| e,
            else => error.IoError,
        };
        while (true) {
            const maybe_item = iter.nextAlloc(sys.allocator, .{ .diags = null }) catch |err| return switch (err) {
                error.OutOfMemory => |e| e,
                else => error.IoError,
            };
            if (maybe_item) |item| {
                try items.append(item);
            } else {
                break;
            }
        }

        return items.toOwnedSlice();
    }

    // Utility
    pub fn collectGarbage() void {
        logger.warn("garbage collection not implemented yet", .{});
    }
};

fn processManagementConnection(allocator: std.mem.Allocator, socket: network.Socket, interface: *SystemInterface) !void {
    const protocol_magic = rpc.protocol_magic;
    const protocol_version: u8 = rpc.protocol_version;

    const reader = socket.reader();
    const writer = socket.writer();

    var remote_auth: [protocol_magic.len]u8 = undefined;
    try reader.readNoEof(&remote_auth);
    if (!std.mem.eql(u8, &remote_auth, &protocol_magic))
        return error.ProtocolMismatch;

    var remote_version = try reader.readIntLittle(u8);
    if (remote_version != protocol_version)
        return error.ProtocolMismatch;

    var end_point = RpcHostEndPoint.init(allocator, reader, writer);
    defer end_point.destroy();

    try end_point.connect(interface);

    try end_point.acceptCalls();
}

fn processManagementConnectionSafe(socket: network.Socket, interface: *SystemInterface) void {
    defer socket.close();

    var thread_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = thread_allocator.deinit();

    processManagementConnection(thread_allocator.allocator(), socket, interface) catch |err| {
        std.log.err("management thread died: {s}", .{@errorName(err)});
        if (builtin.mode == .Debug and builtin.os.tag != .windows) {
            // TODO: Fix windows stack trace printing on wine
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        }
    };
}

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

var current_log_level: std.log.Level = .warn;

const prepared_statement_sources = struct {
    const init_statements = [_][]const u8{
        \\CREATE TABLE IF NOT EXISTS Files (
        \\  uuid TEXT PRIMARY KEY NOT NULL, -- a UUIDv4 that is used as a unique identifier
        \\  user_name TEXT NULL,            -- A text that was given by the user as a human-readable name
        \\  last_change TEXT NOT NULL       -- ISO timestamp when the file was lastly changed.
        \\);
        ,
        \\CREATE TABLE IF NOT EXISTS DataSets (
        \\  checksum TEXT PRIMARY KEY NOT NULL,  -- Hash of the file contents (Blake3, 256 bit, no initial key)
        \\  mime_type TEXT NOT NULL,             -- The mime type
        \\  creation_date TEXT NOT NULL          -- ISO timestamp of when the data set was created
        \\);
        ,
        \\CREATE TABLE IF NOT EXISTS Revisions(
        \\  file TEXT PRIMARY KEY NOT NULL,  -- the file for which this revision was created
        \\  revision INT NOT NULL,           -- Ever-increasing revision number of the file. The biggest number is the latest revision.
        \\  dataset TEXT NOT NULL,            -- Key into the dataset table for which file to reference
        \\  UNIQUE (file, revision),
        \\  FOREIGN KEY (file) REFERENCES Files (uuid),
        \\  FOREIGN KEY (dataset) REFERENCES DataSets (checksum) 
        \\);
        ,
        \\CREATE TABLE IF NOT EXISTS FileTags (
        \\  file TEXT NOT NULL,  -- The key of the file
        \\  tag TEXT NOT NULL,   -- The tag name
        \\  UNIQUE(file,tag),
        \\  FOREIGN KEY (file) REFERENCES Files(uuid)
        \\);
        ,
        \\CREATE VIEW IF NOT EXISTS Tags AS SELECT tag, COUNT(file) AS count FROM FileTags GROUP BY tag
    };

    const file_exists =
        \\SELECT 1 FROM Files WHERE uuid = ?{text}
    ;

    const add_tag =
        \\INSERT INTO FileTags (file, tag) VALUES (?{text}, ?{text}) ON CONFLICT DO NOTHING;
    ;
    const remove_tag =
        \\DELETE FROM FileTags WHERE file = ?{text} AND tag = ?{text}
    ;
    const fetch_file_tags =
        \\SELECT tag FROM FileTags WHERE file = ?{text}
    ;
    const list_tags =
        \\SELECT tag, count FROM Tags WHERE tag LIKE ?{text} ORDER BY count LIMIT ?{u32}
    ;
};

const DatabaseInterface = struct {
    file_exists: sqlite3.StatementType(.{}, prepared_statement_sources.file_exists) = undefined,
    add_tag: sqlite3.StatementType(.{}, prepared_statement_sources.add_tag) = undefined,
    remove_tag: sqlite3.StatementType(.{}, prepared_statement_sources.remove_tag) = undefined,
    fetch_file_tags: sqlite3.StatementType(.{}, prepared_statement_sources.fetch_file_tags) = undefined,
    list_tags: sqlite3.StatementType(.{}, prepared_statement_sources.list_tags) = undefined,
};

const MimeType = struct {
    group: []const u8,
    subtype: ?[]const u8,

    fn parse(str: []const u8) MimeType {
        return if (std.mem.indexOfScalar(u8, str, '/')) |i|
            MimeType{
                .group = str[0..i],
                .subtype = str[i + 1 ..],
            }
        else
            MimeType{ .group = str, .subtype = null };
    }
};

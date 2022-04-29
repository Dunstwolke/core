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
        .dataset_dir = dataset_dir,
        .uuid_source = source,
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
    const FileListItemRaw = struct {
        uuid: []const u8,
        user_name: ?[]const u8,
        last_change: []const u8,
    };

    allocator: std.mem.Allocator,
    global_lock: std.Thread.Mutex = .{},
    db: sqlite3.Db,
    db_intf: DatabaseInterface,
    dataset_dir: std.fs.Dir,
    uuid_source: Uuid.v4.Source,

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

    fn mapSqlError(err: (sqlite3.Error || error{ OutOfMemory, Workaround })) error{ IoError, OutOfMemory } {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.IoError,
        };
    }

    // File management
    pub fn add(rpc_wrap: rpc.AllocatingCall(*SystemInterface), source_file_path: []const u8, mime_type: []const u8, name: ?[]const u8, tags: []const []const u8) rpc.AddFileError!Uuid {
        const sys = rpc_wrap.value;

        if (!std.fs.path.isAbsolute(source_file_path)) {
            return error.InvalidSourceFile;
        }

        var source_file = std.fs.cwd().openFile(source_file_path, .{}) catch |err| return switch (err) {
            error.FileNotFound => error.SourceFileNotFound,
            error.AccessDenied => error.AccessDenied,
            else => return error.IoError,
        };
        defer source_file.close();

        const file_hash = try computeFileHash(source_file);
        source_file.seekTo(0) catch return error.IoError; // rewind the file

        const file_title = name orelse try determineFileTitle(
            rpc_wrap.allocator,
            source_file_path,
            source_file,
            MimeType.parse(mime_type),
        );

        // Everything before this point is not required to be serialized with the database access.
        sys.lock();
        defer sys.unlock();

        const dataset = sys.addDataset(rpc_wrap.allocator, mime_type, source_file, file_hash) catch |err| return switch (err) {
            error.AccessDenied => error.AccessDenied,
            else => error.IoError,
        };
        const file_dataset = sqlite3.Text{ .data = &dataset.checksum };

        // TODO: Implement file deduplication again:
        // const ExistingFile = struct {
        //     file: []const u8,
        //     revision: u32,
        // };

        // if (try stmt_any_exists.oneAlloc(ExistingFile, arena.allocator(), .{}, .{ .dataset = file_dataset })) |existing| {
        //     std.log.err("The contents of this file are already available in file {s}, revision {d}!", .{
        //         existing.file,
        //         existing.revision,
        //     });
        //     return 1;
        // }

        const file_uuid = sys.uuid_source.create();
        const file_uuid_str = uuidToString(file_uuid);
        const file_uuid_text = sqlite3.Text{ .data = &file_uuid_str };

        sys.db_intf.create_file.exec(.{}, .{
            file_uuid_text,
            file_title,
        }) catch |err| return mapSqlError(err);
        sys.db_intf.add_revision.exec(.{}, .{
            file_uuid_text,
            file_dataset,
            file_uuid_text,
        }) catch |err| return mapSqlError(err);

        logger.info("created file({s}, {s}, {s}, {s})", .{ file_title, mime_type, &dataset.checksum, dataset.creation_date });

        for (tags) |tag_string| {
            const tag = sqlite3.Text{ .data = tag_string };
            sys.db_intf.add_tag.reset();
            sys.db_intf.add_tag.exec(.{}, .{
                .file = file_uuid_text,
                .tag = tag,
            }) catch |err| return mapSqlError(err);
        }

        return file_uuid;
    }

    pub fn update(file: Uuid, source_file: []const u8, mime: []const u8) rpc.UpdateFileError!void {
        _ = file;
        _ = source_file;
        _ = mime;
        @panic("not implemented yet");
    }

    pub fn rename(sys: *SystemInterface, file: Uuid, maybe_name: ?[]const u8) rpc.RenameFileError!void {
        sys.lock();
        defer sys.unlock();

        var canonical_format = try sys.assertFile(file);
        var uuid_text = sqlite3.Text{ .data = &canonical_format };

        if (maybe_name) |name| {
            const name_text = sqlite3.Text{ .data = name };

            sys.db_intf.set_file_name.reset();
            sys.db_intf.set_file_name.exec(.{}, .{
                name_text,
                uuid_text,
            }) catch |err| return mapSqlError(err);
        } else {
            sys.db_intf.delete_file_name.reset();
            sys.db_intf.delete_file_name.exec(.{}, .{
                uuid_text,
            }) catch |err| return mapSqlError(err);
        }
    }

    pub fn delete(sys: *SystemInterface, file: Uuid) rpc.RemoveFileError!void {
        sys.lock();
        defer sys.unlock();

        var canonical_format = try sys.assertFile(file);
        var uuid_text = sqlite3.Text{ .data = &canonical_format };

        sys.db_intf.delete_all_revisions.reset();
        sys.db_intf.delete_all_revisions.exec(.{}, .{uuid_text}) catch |err| return mapSqlError(err);

        sys.db_intf.delete_all_tags.reset();
        sys.db_intf.delete_all_tags.exec(.{}, .{uuid_text}) catch |err| return mapSqlError(err);

        sys.db_intf.delete_file.reset();
        sys.db_intf.delete_file.exec(.{}, .{uuid_text}) catch |err| return mapSqlError(err);
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

    pub fn info(rpc_wrap: rpc.AllocatingCall(*SystemInterface), file: Uuid) rpc.FileInfoError!rpc.FileInfo {
        const sys = rpc_wrap.value;
        sys.lock();
        defer sys.unlock();

        const Tag = struct {
            uuid: []const u8,
            user_name: ?[]const u8,
            last_change: []const u8,
        };

        var canonical_format = try sys.assertFile(file);
        var uuid_text = sqlite3.Text{ .data = &canonical_format };

        sys.db_intf.query_file_info.reset();
        sys.db_intf.query_file_tags.reset();
        sys.db_intf.query_file_revs.reset();

        const tag_or_null = sys.db_intf.query_file_info.oneAlloc(Tag, rpc_wrap.allocator, .{}, .{uuid_text}) catch |err| return mapSqlError(err);

        const tag: Tag = tag_or_null orelse return error.FileNotFound;

        const Revision = struct {
            revision: u32,
            dataset: []const u8,
            mime_type: []const u8,
            creation_date: []const u8,
        };

        const tags: [][]const u8 = sys.db_intf.query_file_tags.all([]const u8, rpc_wrap.allocator, .{}, .{uuid_text}) catch |err| return mapSqlError(err);
        const revisions: []Revision = sys.db_intf.query_file_revs.all(Revision, rpc_wrap.allocator, .{}, .{uuid_text}) catch |err| return mapSqlError(err);

        const revs = try rpc_wrap.allocator.alloc(rpc.Revision, revisions.len);

        for (revs) |*rev, i| {
            const src = revisions[i];
            rev.* = rpc.Revision{
                .number = src.revision,
                .dataset = src.dataset[0..32].*,
                .date = src.creation_date[0..19].*,
                .mime = "", // TODO: Implement these
                .size = 0, // TODO: Implement these
            };
        }

        return rpc.FileInfo{
            .name = tag.user_name,
            .revisions = revs,
            .tags = tags,
            .last_change = tag.last_change[0..19].*,
        };
    }

    pub fn list(rpc_wrap: rpc.AllocatingCall(*SystemInterface), skip: u32, limit: ?u32, include_filters: []const []const u8, exclude_filters: []const []const u8) rpc.ListFilesError![]rpc.FileListItem {
        const sys = rpc_wrap.value;
        sys.lock();
        defer sys.unlock();

        var diag = sqlite3.Diagnostics{};
        errdefer std.log.err("sqlite failed: {}", .{diag});

        const query_text = blk: {
            var builder = std.ArrayList(u8).init(rpc_wrap.allocator);
            defer builder.deinit();

            const writer = builder.writer();

            try writer.writeAll(
                \\SELECT
                \\    Files.uuid,
                \\    Files.user_name,
                \\    Files.last_change
                \\  FROM Files
                \\  LEFT JOIN FileTags ON Files.uuid = FileTags.file
            );
            if (include_filters.len > 0 or exclude_filters.len > 0) {
                try writer.writeAll(
                    \\
                    \\  WHERE
                );

                var first = true;

                for (include_filters) |tag| {
                    defer first = false;
                    if (first) {
                        try writer.writeAll("\n       ");
                    } else {
                        try writer.writeAll("\n   AND ");
                    }
                    try writer.print("(FileTags.tag LIKE '{s}')", .{tag});
                }
                for (exclude_filters) |tag| {
                    defer first = false;
                    if (first) {
                        try writer.writeAll("\n       ");
                    } else {
                        try writer.writeAll("\n   AND ");
                    }
                    try writer.print("NOT (FileTags.tag LIKE '{s}')", .{tag});
                }
            }

            try writer.writeAll(
                \\
                \\  GROUP BY Files.uuid, Files.user_name, Files.last_change
                \\  ORDER BY last_change DESC
                \\  LIMIT :count OFFSET :offset
            );

            break :blk builder.toOwnedSlice();
        };
        defer rpc_wrap.allocator.free(query_text);

        // std.debug.print("{s}\n", .{query_text});

        var query = sys.db.prepareDynamic(query_text) catch |err| return switch (err) {
            else => error.IoError,
        };
        defer query.deinit();

        const real_limit: u32 = limit orelse @as(u32, std.math.maxInt(u32));
        var iter = query.iterator(FileListItemRaw, .{
            .count = real_limit,
            .offset = skip,
        }) catch |err| return switch (err) {
            else => error.IoError,
        };

        var items = std.ArrayList(rpc.FileListItem).init(rpc_wrap.allocator);
        defer items.deinit();

        while (true) {
            const maybe_item = iter.nextAlloc(rpc_wrap.allocator, .{ .diags = null }) catch |err| return switch (err) {
                error.OutOfMemory => |e| e,
                else => error.IoError,
            };
            const item = maybe_item orelse break;
            try items.append(rpc.FileListItem{
                .uuid = Uuid.parse(item.uuid) catch |e| {
                    std.log.err("failed to parse uuid {s}: {s}. Skipping item.", .{ item.uuid, @errorName(e) });
                    continue;
                },
                .user_name = item.user_name,
                .last_change = item.last_change,
            });
        }

        return items.toOwnedSlice();
    }

    pub fn find(rpc_wrap: rpc.AllocatingCall(*SystemInterface), skip: u32, limit: ?u32, filter: []const u8, exact: bool) rpc.ListFilesError![]rpc.FileListItem {
        const sys = rpc_wrap.value;
        sys.lock();
        defer sys.unlock();

        const real_limit: u32 = limit orelse std.math.maxInt(u32);

        var real_filter = sqlite3.Text{ .data = filter };
        if (!exact) {
            real_filter.data = try std.fmt.allocPrint(rpc_wrap.allocator, "%{s}%", .{filter});
        }

        sys.db_intf.find_file.reset();
        var iter = sys.db_intf.find_file.iterator(FileListItemRaw, .{
            real_filter,
            real_limit,
            skip,
        }) catch |err| return switch (err) {
            else => error.IoError,
        };

        var items = std.ArrayList(rpc.FileListItem).init(rpc_wrap.allocator);
        defer items.deinit();

        while (true) {
            const maybe_item = iter.nextAlloc(rpc_wrap.allocator, .{ .diags = null }) catch |err| return switch (err) {
                error.OutOfMemory => |e| e,
                else => error.IoError,
            };
            const item = maybe_item orelse break;
            try items.append(rpc.FileListItem{
                .uuid = Uuid.parse(item.uuid) catch |e| {
                    std.log.err("failed to parse uuid {s}: {s}. Skipping item.", .{ item.uuid, @errorName(e) });
                    continue;
                },
                .user_name = item.user_name,
                .last_change = item.last_change,
            });
        }

        return items.toOwnedSlice();
    }

    fn assertFile(sys: *SystemInterface, file: Uuid) ![36]u8 {
        var canonical_format = uuidToString(file);
        const uuid_text = sqlite3.Text{ .data = &canonical_format };

        sys.db_intf.file_exists.reset();
        const maybe_result = sys.db_intf.file_exists.one(u32, .{}, .{uuid_text}) catch return error.IoError;
        if (maybe_result == null) {
            return error.FileNotFound;
        }

        return canonical_format;
    }

    // Tag management
    pub fn addTags(rpc_wrap: rpc.AllocatingCall(*SystemInterface), file: Uuid, tags: []const []const u8) rpc.AddTagError!void {
        const sys = rpc_wrap.value;

        sys.lock();
        defer sys.unlock();

        var canonical_format = try sys.assertFile(file);
        var uuid_text = sqlite3.Text{ .data = &canonical_format };

        for (tags) |tag| {
            var tag_text = sqlite3.Text{ .data = tag };
            sys.db_intf.add_tag.reset();
            sys.db_intf.add_tag.exec(.{}, .{ uuid_text, tag_text }) catch |err| {
                std.log.warn("failed to add tag: {s}", .{@errorName(err)});
                return error.IoError;
            };
        }
    }

    pub fn removeTags(rpc_wrap: rpc.AllocatingCall(*SystemInterface), file: Uuid, tags: []const []const u8) rpc.RemoveTagError!void {
        const sys = rpc_wrap.value;

        sys.lock();
        defer sys.unlock();

        var canonical_format = try sys.assertFile(file);
        var uuid_text = sqlite3.Text{ .data = &canonical_format };

        for (tags) |tag| {
            var tag_text = sqlite3.Text{ .data = tag };
            sys.db_intf.remove_tag.reset();
            sys.db_intf.remove_tag.exec(.{}, .{ uuid_text, tag_text }) catch |err| {
                std.log.warn("failed to remove tag: {s}", .{@errorName(err)});
                return error.IoError;
            };
        }
    }

    pub fn listFileTags(rpc_wrap: rpc.AllocatingCall(*SystemInterface), file: Uuid) rpc.ListFileTagsError![]const []const u8 {
        const sys = rpc_wrap.value;

        sys.lock();
        defer sys.unlock();

        var canonical_format = try sys.assertFile(file);
        const uuid_text = sqlite3.Text{ .data = &canonical_format };

        sys.db_intf.fetch_file_tags.reset();
        return sys.db_intf.fetch_file_tags.all(
            []const u8,
            rpc_wrap.allocator,
            .{},
            .{uuid_text},
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
    }

    pub fn listTags(rpc_wrap: rpc.AllocatingCall(*SystemInterface), filter: ?[]const u8, limit: ?u32) rpc.ListTagsError![]rpc.TagInfo {
        const sys = rpc_wrap.value;

        sys.lock();
        defer sys.unlock();

        const real_limit: u32 = limit orelse std.math.maxInt(u32);
        const real_filter = sqlite3.Text{ .data = filter orelse "%" };

        var items = std.ArrayList(rpc.TagInfo).init(rpc_wrap.allocator);
        defer items.deinit();

        sys.db_intf.list_tags.reset();
        var iter = sys.db_intf.list_tags.iterator(rpc.TagInfo, .{ .filter = real_filter, .limit = real_limit }) catch |err| return switch (err) {
            error.OutOfMemory => |e| e,
            else => error.IoError,
        };
        while (true) {
            const maybe_item = iter.nextAlloc(rpc_wrap.allocator, .{ .diags = null }) catch |err| return switch (err) {
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
    pub fn collectGarbage(sys: *SystemInterface) void {
        _ = sys;
        logger.warn("garbage collection not implemented yet", .{});
    }

    const Dataset = struct {
        checksum: [64]u8,
        mime_type: []const u8,
        creation_date: []const u8,
    };
    fn addDataset(
        sys: *SystemInterface,
        allocator: std.mem.Allocator,
        mime_type: []const u8,
        source_file: std.fs.File,
        file_hash: [32]u8,
    ) !Dataset {
        var hash_str: [64]u8 = undefined;
        _ = std.fmt.bufPrint(&hash_str, "{}", .{std.fmt.fmtSliceHexLower(&file_hash)}) catch unreachable;

        const hash_text = sqlite3.Text{ .data = &hash_str };
        const mime_text = sqlite3.Text{ .data = mime_type };

        sys.db_intf.fetch_dataset.reset();
        if (try sys.db_intf.fetch_dataset.oneAlloc(Dataset, allocator, .{}, .{hash_text})) |dataset_desc| {
            // we already have this dataset, be happy :)
            return dataset_desc;
        }

        sys.db_intf.create_dataset.reset();
        try sys.db_intf.create_dataset.exec(.{}, .{
            hash_text,
            mime_text,
        });

        sys.db_intf.fetch_dataset.reset();
        const dataset_desc = (try sys.db_intf.fetch_dataset.oneAlloc(Dataset, allocator, .{}, .{hash_text})) orelse {
            @panic("unprotected race condition"); // race condition, someone deleted the file very tightly between insert_stmt and this.
        };

        errdefer sys.dataset_dir.deleteFile(&hash_str) catch |err| logger.err("failed to delete incomplete file {s}: {s}", .{ &hash_str, @errorName(err) });

        var output_file = try sys.dataset_dir.createFile(&hash_str, .{});
        defer output_file.close();

        var fifo = std.fifo.LinearFifo(u8, .{ .Static = 8192 }).init();

        try fifo.pump(source_file.reader(), output_file.writer());

        return dataset_desc;
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

    end_point.acceptCalls() catch |err| switch (err) {
        error.EndOfStream => {}, // this is just a safe disconnect
        else => |e| {
            logger.err("client connection failed: {s}", .{@errorName(e)});
            if (builtin.mode == .Debug) {
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
            }
            return e;
        },
    };
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
    const find_file =
        \\SELECT * FROM Files WHERE user_name LIKE ?{text} ORDER BY user_name LIMIT ?{u32} OFFSET ?{u32}
    ;
    const query_file_info =
        \\SELECT uuid, user_name, last_change FROM Files WHERE uuid = ?{text}
    ;
    const query_file_tags =
        \\SELECT tag FROM FileTags WHERE file = ?{text} ORDER BY tag
    ;
    const query_file_revs =
        \\SELECT Revisions.revision, Revisions.dataset, DataSets.mime_type, DataSets.creation_date FROM Revisions
        \\  LEFT JOIN DataSets ON Revisions.dataset = DataSets.checksum
        \\  WHERE file = ?{text}
        \\  ORDER BY Revisions.revision desc
    ;
    const query_file_name =
        \\SELECT user_name FROM Files WHERE uuid = ?{text}
    ;
    const set_file_name =
        \\UPDATE Files SET user_name = ?{text} WHERE uuid = ?{text}
    ;
    const delete_file_name =
        \\UPDATE Files SET user_name = NULL WHERE uuid = ?{text}
    ;
    const any_rev_exists =
        \\SELECT file, revision FROM Revisions WHERE dataset = :dataset
    ;
    const create_file =
        \\INSERT INTO Files (uuid, user_name, last_change) VALUES (:file, :name, CURRENT_TIMESTAMP);
    ;
    const add_revision =
        \\INSERT INTO Revisions (file, dataset, revision) VALUES (:file, :dataset, (SELECT IFNULL(MAX(revision),0)+1 FROM Revisions WHERE file = :file LIMIT 1));
    ;
    const create_dataset =
        \\INSERT INTO DataSets (checksum, mime_type, creation_date) VALUES (?{text}, ?{text}, CURRENT_TIMESTAMP) 
    ;
    const fetch_dataset =
        \\SELECT checksum, mime_type, creation_date FROM DataSets WHERE checksum = ?{text}
    ;
    const delete_all_revisions =
        \\DELETE FROM Revisions WHERE file = ?{text}
    ;
    const delete_all_tags =
        \\DELETE FROM FileTags WHERE file = ?{text}
    ;
    const delete_file =
        \\DELETE FROM Files WHERE uuid = ?{text}
    ;
};

const DatabaseInterface = struct {
    file_exists: sqlite3.StatementType(.{}, prepared_statement_sources.file_exists) = undefined,
    add_tag: sqlite3.StatementType(.{}, prepared_statement_sources.add_tag) = undefined,
    remove_tag: sqlite3.StatementType(.{}, prepared_statement_sources.remove_tag) = undefined,
    fetch_file_tags: sqlite3.StatementType(.{}, prepared_statement_sources.fetch_file_tags) = undefined,
    list_tags: sqlite3.StatementType(.{}, prepared_statement_sources.list_tags) = undefined,
    find_file: sqlite3.StatementType(.{}, prepared_statement_sources.find_file) = undefined,
    query_file_info: sqlite3.StatementType(.{}, prepared_statement_sources.query_file_info) = undefined,
    query_file_tags: sqlite3.StatementType(.{}, prepared_statement_sources.query_file_tags) = undefined,
    query_file_revs: sqlite3.StatementType(.{}, prepared_statement_sources.query_file_revs) = undefined,
    query_file_name: sqlite3.StatementType(.{}, prepared_statement_sources.query_file_name) = undefined,
    set_file_name: sqlite3.StatementType(.{}, prepared_statement_sources.set_file_name) = undefined,
    delete_file_name: sqlite3.StatementType(.{}, prepared_statement_sources.delete_file_name) = undefined,
    any_rev_exists: sqlite3.StatementType(.{}, prepared_statement_sources.any_rev_exists) = undefined,
    create_file: sqlite3.StatementType(.{}, prepared_statement_sources.create_file) = undefined,
    add_revision: sqlite3.StatementType(.{}, prepared_statement_sources.add_revision) = undefined,
    create_dataset: sqlite3.StatementType(.{}, prepared_statement_sources.create_dataset) = undefined,
    fetch_dataset: sqlite3.StatementType(.{}, prepared_statement_sources.fetch_dataset) = undefined,
    delete_all_revisions: sqlite3.StatementType(.{}, prepared_statement_sources.delete_all_revisions) = undefined,
    delete_all_tags: sqlite3.StatementType(.{}, prepared_statement_sources.delete_all_tags) = undefined,
    delete_file: sqlite3.StatementType(.{}, prepared_statement_sources.delete_file) = undefined,
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

fn makeCanonicalUuid(uuid_str: []const u8) ![36]u8 {
    const uuid = Uuid.parse(uuid_str) catch |err| {
        logger.err("'{s}' is not a valid uuid: {s}", .{ uuid_str, @errorName(err) });
        return err;
    };
    return uuidToString(uuid);
}

fn uuidToString(uuid: Uuid) [36]u8 {
    var canonical_format: [36]u8 = undefined;
    uuid.formatBuf(&canonical_format) catch unreachable; // we provide enough space
    return canonical_format;
}

fn determineFileTitle(allocator: std.mem.Allocator, file_path: []const u8, file: std.fs.File, mime: MimeType) ![]const u8 {

    // TODO: Implement improved guessing of file titles.
    // Possible sources:
    // - IDv3
    // - PDF Title
    // - Markdown first

    _ = allocator;
    _ = mime;
    _ = file;

    const basename = std.fs.path.basename(file_path);
    const ext = std.fs.path.extension(basename);
    return basename[0 .. basename.len - ext.len];
}

fn computeFileHash(file: std.fs.File) ![32]u8 {
    var blake_hash = std.crypto.hash.Blake3.init(.{ .key = null });
    while (true) {
        var buffer: [8192]u8 = undefined;
        const len = file.read(&buffer) catch return error.IoError;
        if (len == 0)
            break;
        blake_hash.update(buffer[0..len]);
    }

    var final: [32]u8 = undefined;
    blake_hash.final(&final);
    return final;
}

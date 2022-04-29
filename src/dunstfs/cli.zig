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
        \\dfs [options] <verb> [verb options]
        \\
        \\  -h, --help     Will output this text.
        \\  -v, --verbose  Will output more detailled information about what happens.
        \\      --version  Prints the current version number
        \\  -j, --json     Will output JSON data instead of human readable text.
        \\  -y, --yes      Will auto-confirm user questions with "y".
        \\
        \\Verbs:
        \\  add <path> [--mime <type>] [--name <name>] [tag] [tag] [tag] ...
        \\    Adds a new file at <path> to the DunstFS and adds all additional tags to it.
        \\    Will automatically add a mime type tag if it can be detected via `file --brief --mime-type` as
        \\    well as a date tag for the creation date.
        \\    Will output the file guid to stdout.
        \\    This action fails when the file is already existent (determined by its hash)
        \\    When --name <name> is given, the name of the file will be set to this, otherwise a name will be
        \\    guessed from the file contents or the file name.
        \\
        \\  ls [--count n] [tag] [-tag] [tag] ...
        \\    Lists the last 25 files that matches the tag filters. Tags can use wildcards here
        \\    to filter out files that are not of interest. Tags prefixed with - will be excluded
        \\    the result set.
        \\    Files will be listed newest-to-oldest so it's easier to find actively used files again.
        \\    If --count is provided, the 25 is replaced by the requested number of files.
        \\
        \\  tag <guid> [+tag] [-tag] ...
        \\    Modify tags of the file with <guid>.
        \\    Adds all tags without a prefix or + prefix. Removes tags with - prefix.
        \\    Allows the use of tag wildcards for removal.
        \\    After that, all tags for this file will be printed.
        \\
        \\  rm <guid> <guid> <guid> ...
        \\    Removes the file with <guid> from DunstFS.
        \\
        \\  get <guid> [-o <path>]
        \\    Fetches the file <guid> and will write it to <path>. If no <path> is given,
        \\    it will be written as <guid>.<ext> to the current working directory with <ext>
        \\    determined by the mime type.
        \\
        \\  update <guid> <path> [--mime <type>]
        \\    Replaces the contents of the file <guid> with the contents of the file at <path>.
        \\    This will create a new revision of the file, which allows to roll back to previous versions.
        \\
        \\  info <guid>
        \\    Prints out information about the file <guid>. Includes a list of all revisions, tags and meta data.
        \\
        \\  name <guid> [<hname>]
        \\    Will give the file <guid> a human readable name determined by <hname>. This is similar to a file name,
        \\    but is not required to follow any rules. Anything can be set here.
        \\    If <hname> is not given
        \\
        \\  find [--count n] [--exact] <hname>
        \\    Finds files based on their human readable name. Allows globbing on <hname>.
        \\    If --count n is given, will limit the number of files returned to n.
        \\    If --exact is given, the match must fully fit. Otherwise, any prefix and postfix might be allowed.
        \\
        \\  tags [--count n] [pattern]
        \\    Prints out all tags and the number of files that match those. If [pattern] is given, the tags will be
        \\    filtered by the [pattern].
        \\    When [--count n] is present, only the n most important tags will be printed.
        \\
        \\  gc [--dry-run]
        \\    Collects all data sets that are currently not in use and deletes them.
        \\    When --dry-run is set, it will only list the files deleted, but won't actually delete them.
        \\
        \\Tags & Tag Wildcards:
        \\  DunstFS uses a hierarchical tag architecture that allows quick selection of fitting tags.
        \\  Each tag can have several sub-components which are separated by /:
        \\  - 2021
        \\  - 2021/09
        \\  - 2021/09/13
        \\  Tags can be wildcard-filtered by using ? and * globbing where ? matches *any* character, but only one,
        \\  and * matches an arbitrary sequence of characters, including the zero length sequence.
        \\  Note that / is excluded from both matching patterns, but a tag will match any other tag
        \\  that contains sub-tags.
        \\  Thus, the tag "image/png" could be matched with:
        \\  - "image"
        \\  - "image/*"
        \\   - "*/png"
        \\   - "*/*"
        \\   - "image/???"
        \\
    );
}

const std = @import("std");
const builtin = @import("builtin");
const args_parser = @import("args");
const known_folders = @import("known-folders");
const Uuid = @import("uuid6");

const libmagic = @import("magic.zig");
const MagicSet = libmagic.MagicSet;

const RpcClient = @import("RpcClient.zig");

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

var current_log_level: std.log.Level = .warn;

const CommonOptions = struct {
    help: bool = false,
    verbose: bool = false,
    version: bool = false,
    json: bool = false,
    yes: bool = false,
    host: ?[]const u8 = null,

    pub const shorthands = .{
        .h = "help",
        .v = "verbose",
        .j = "json",
        .y = "yes",
    };
};

const Verb = union(enum) {
    help: HelpOptions,
    add: AddOptions,
    ls: LsOptions,
    tag: TagOptions,
    rm: RmOptions,
    get: GetOptions,
    update: UpdateOptions,
    info: InfoOptions,
    name: NameOptions,
    find: FindOptions,
    tags: TagsOptions,
    gc: GcOptions,

    const EmptyOptions = struct {};

    const HelpOptions = EmptyOptions;
    const AddOptions = struct {
        mime: ?[]const u8 = null,
        name: ?[]const u8 = null,
    };
    const LsOptions = struct {
        skip: u32 = 0,
        count: u32 = 25,

        pub const shorthands = .{
            .c = "count",
        };
    };
    const TagOptions = EmptyOptions;
    const RmOptions = struct {};
    const GetOptions = struct {
        output: ?[]const u8 = null,

        pub const shorthands = .{
            .o = "output",
        };
    };
    const UpdateOptions = struct {
        mime: ?[]const u8 = null,
    };
    const InfoOptions = EmptyOptions;
    const NameOptions = struct {
        delete: bool = false,
    };
    const FindOptions = struct {
        skip: u32 = 0,
        count: ?u32 = null,
        exact: bool = false,

        pub const shorthands = .{
            .c = "count",
            .x = "exact",
        };
    };
    const TagsOptions = struct {
        count: ?u32 = null,

        pub const shorthands = .{
            .c = "count",
        };
    };
    const GcOptions = struct {
        @"dry-run": bool = false,
        verify: bool = false,
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

    var cli = args_parser.parseWithVerbForCurrentProcess(CommonOptions, Verb, global_allocator, .print) catch return 1;
    defer cli.deinit();

    var stdout_raw = std.io.getStdOut().writer();

    var buffered_stdout = std.io.bufferedWriter(stdout_raw);
    defer buffered_stdout.flush() catch {}; // well, we can't do anything anymore here anyways

    var stdout = buffered_stdout.writer();

    // Do opt early out when invoking help command, as we don't need to initialize anything here.
    if (cli.options.help or (cli.verb == null) or (cli.verb.? == .help)) {
        try printUsage(stdout);
        return 0;
    }

    if (cli.options.version) {
        if (cli.options.json) {
            try stdout.print(
                \\{{ "major": {d}, "minor": {d}, "patch": {d} }}
                \\
            , .{ version.major, version.minor, version.patch });
        } else {
            try stdout.print("DunstFS {}.{}.{}\n", .{ version.major, version.minor, version.patch });
        }
        return 0;
    }

    if (cli.options.verbose)
        current_log_level = .info;

    const magic = try MagicSet.openBuiltin();
    defer magic.close();

    logger.info("Clone working directory...", .{});
    var working_directory = try std.fs.cwd().openDir(".", .{});
    defer working_directory.close();

    logger.info("Connect to daemon...", .{});

    var rpc = RpcClient.connect(gpa.allocator(), cli.options.host) catch |err| {
        logger.err("could not connect to rpc daemon: {s}", .{@errorName(err)});
        return 1;
    };
    defer rpc.deinit();

    logger.info("Begin processing verb '{s}'...", .{std.meta.tagName(cli.verb.?)});

    switch (cli.verb.?) {
        .add => |verb| {
            if (cli.positionals.len < 1) {
                logger.err("add requires at least a file name!", .{});
                return 1;
            }

            var source_path_raw = try working_directory.realpathAlloc(global_allocator, cli.positionals[0]);
            defer global_allocator.free(source_path_raw);

            source_path_raw = try global_allocator.realloc(source_path_raw, source_path_raw.len + 1);
            source_path_raw[source_path_raw.len - 1] = 0;

            const source_path = source_path_raw[0 .. source_path_raw.len - 1 :0];

            const detected_mime = verb.mime orelse if (@as(?[*:0]const u8, magic.file(source_path))) |mime_str| std.mem.span(mime_str) else {
                logger.err("could not detect mime type: {s}", .{magic.getError()});
                return 1;
            };

            const file_uuid = try rpc.add(
                source_path,
                detected_mime,
                verb.name,
                cli.positionals[1..],
            );

            if (cli.options.json) {
                var buf: [36]u8 = undefined;
                file_uuid.formatBuf(&buf) catch unreachable;
                try std.json.stringify(@as([]const u8, &buf), .{}, stdout);
            } else {
                try stdout.print("Created new file:\n{}\n", .{file_uuid});
            }
        },

        .ls => |verb| {
            var include_tags = std.ArrayList([]const u8).init(global_allocator);
            var exclude_tags = std.ArrayList([]const u8).init(global_allocator);

            defer include_tags.deinit();
            defer exclude_tags.deinit();

            for (cli.positionals) |item| {
                if (std.mem.startsWith(u8, item, "-")) {
                    try exclude_tags.append(item[1..]);
                } else {
                    try include_tags.append(item[1..]);
                }
            }

            var items = try rpc.list(global_allocator, verb.skip, verb.count, include_tags.items, exclude_tags.items);
            defer RpcClient.free(global_allocator, @TypeOf(items), &items);

            try renderFileList(items, cli.options.json);
        },

        .find => |verb| {
            if (cli.positionals.len != 1) {
                logger.err("find requires a search option!", .{});
                return 1;
            }

            var items = try rpc.find(global_allocator, verb.skip, verb.count, cli.positionals[0], verb.exact);
            defer RpcClient.free(global_allocator, @TypeOf(items), &items);

            try renderFileList(items, cli.options.json);
        },

        .tag => {
            if (cli.positionals.len < 1) {
                logger.err("tag requires the file identifier!", .{});
                return 1;
            }

            const file_uuid = Uuid.parse(cli.positionals[0]) catch {
                logger.err("{s} is not a valid file identifier", .{cli.positionals[0]});
                return 1;
            };

            var added_tags = std.ArrayList([]const u8).init(global_allocator);
            var removed_tags = std.ArrayList([]const u8).init(global_allocator);

            defer added_tags.deinit();
            defer removed_tags.deinit();

            for (cli.positionals[1..]) |tag_def| {
                if (std.mem.startsWith(u8, tag_def, "-")) {
                    try removed_tags.append(tag_def[1..]);
                } else {
                    try added_tags.append(tag_def);
                }
            }

            if (removed_tags.items.len > 0) {
                rpc.removeTags(file_uuid, removed_tags.items) catch |err| switch (err) {
                    error.FileNotFound => {
                        logger.err("The file {} does not exist!", .{file_uuid});
                        return 1;
                    },

                    else => |e| return e,
                };
            }

            if (added_tags.items.len > 0) {
                rpc.addTags(file_uuid, added_tags.items) catch |err| switch (err) {
                    error.FileNotFound => {
                        logger.err("The file {} does not exist!", .{file_uuid});
                        return 1;
                    },

                    else => |e| return e,
                };
            }

            var file_tags = rpc.listFileTags(global_allocator, file_uuid) catch |err| switch (err) {
                error.FileNotFound => {
                    logger.err("The file {} does not exist!", .{file_uuid});
                    return 1;
                },

                else => |e| return e,
            };
            defer RpcClient.free(global_allocator, @TypeOf(file_tags), &file_tags);

            if (cli.options.json) {
                try std.json.stringify(file_tags, .{}, stdout);
            } else {
                for (file_tags) |tag| {
                    try stdout.writeAll(tag);
                    try stdout.writeAll("\n");
                }
            }
        },

        .rm => {
            // rough process:
            // 1. find file
            // 2. unlink all datasets
            // 3. remove all tags
            // 4. delete file

            for (cli.positionals) |file_id| {
                _ = Uuid.parse(file_id) catch {
                    logger.err("{s} is not a valid file identifier", .{file_id});
                    return 1;
                };
            }

            for (cli.positionals) |file_id| {
                const file_uuid = Uuid.parse(file_id) catch unreachable;

                rpc.delete(file_uuid) catch |err| switch (err) {
                    error.FileNotFound => logger.err("The file {} does not exist!", .{file_uuid}),
                    else => |e| return e,
                };
            }
        },

        .get => |verb| {
            logger.err("'get' not implemented yet. verb data: {}", .{verb});
        },

        .update => |verb| {
            logger.err("'update' not implemented yet. verb data: {}", .{verb});
        },

        .info => {
            if (cli.positionals.len != 1) {
                logger.err("info requires a file id", .{});
                return 1;
            }

            const file_uuid = Uuid.parse(cli.positionals[0]) catch {
                logger.err("{s} is not a valid file identifier", .{cli.positionals[0]});
                return 1;
            };

            var info = try rpc.info(global_allocator, file_uuid);
            defer RpcClient.free(global_allocator, @TypeOf(info), &info);

            if (cli.options.json) {
                var json = std.json.writeStream(stdout, 5);

                try json.beginObject();

                try json.objectField("uuid");
                try json.emitString(cli.positionals[0]);

                try json.objectField("name");
                if (info.name) |user_name| {
                    try json.emitString(user_name);
                } else {
                    try json.emitNull();
                }

                try json.objectField("last_change");
                try json.emitString(&info.last_change);

                try json.objectField("tags");
                try json.beginArray();
                for (info.tags) |file_tag| {
                    try json.arrayElem();
                    try json.emitString(file_tag);
                }
                try json.endArray();

                try json.objectField("revisions");
                try json.beginArray();
                for (info.revisions) |rev| {
                    try json.arrayElem();
                    try json.beginObject();

                    try json.objectField("revision");
                    try json.emitNumber(rev.number);
                    try json.objectField("creation_date");
                    try json.emitString(&rev.date);
                    try json.objectField("mime_type");
                    try json.emitString(rev.mime);
                    try json.objectField("dataset");
                    try json.emitString(&rev.dataset);

                    try json.endObject();
                }
                try json.endArray();

                try json.endObject();

                try stdout.writeAll("\n");
            } else {
                try stdout.print("UUID:        {s}\n", .{cli.positionals[0]});
                try stdout.print("Name:        {s}\n", .{info.name});
                try stdout.print("Last Change: {s}\n", .{info.last_change});

                try stdout.writeAll("Tags:        ");
                for (info.tags) |file_tag, i| {
                    if ((i % 10) == 9) {
                        try stdout.writeAll(",\n             ");
                    } else if (i > 0) {
                        try stdout.writeAll(", ");
                    }
                    try stdout.writeAll(file_tag);
                }

                try stdout.writeAll("\n");

                try stdout.writeAll("Revisions:\n");
                for (info.revisions) |rev| {
                    // mimes are typically not longer than "application/vnd.uplanet.bearer-choice-wbxml", so 45 is a reasonable choice here.
                    // there are longer mime types, but those are very special
                    try stdout.print("- Revision {d:0>3} ({s}):\n  Mime = {s: <45}\n  Data Set = {s}\n", .{
                        rev.number,
                        rev.date,
                        rev.mime,
                        rev.dataset,
                    });
                }
            }
        },

        .name => |verb| {
            if (cli.positionals.len == 0) {
                logger.err("name requires a file id", .{});
                return 1;
            }

            if (cli.positionals.len > 2) {
                logger.err("name only takes a file id and a name.", .{});
                return 1;
            }

            if (verb.delete and cli.positionals.len > 1) {
                logger.err("deleting a name must only have the file id.", .{});
                return 1;
            }

            const file_uuid = Uuid.parse(cli.positionals[0]) catch {
                logger.err("{s} is not a valid file identifier", .{cli.positionals[0]});
                return 1;
            };

            if (verb.delete) {
                try rpc.rename(file_uuid, null);
                return 0;
            }

            switch (cli.positionals.len) {
                1 => { // query

                    var info = try rpc.info(global_allocator, file_uuid);
                    defer RpcClient.free(global_allocator, @TypeOf(info), &info);

                    if (cli.options.json) {
                        try std.json.stringify(.{
                            .file = cli.positionals[0],
                            .name = info.name,
                        }, .{}, stdout);
                        try stdout.writeAll("\n");
                    } else {
                        if (info.name) |user_name| {
                            try stdout.writeAll(user_name);
                            try stdout.writeAll("\n");
                        } else {
                            logger.warn("The file {} does not have a name assigned yet!", .{file_uuid});
                            return 1;
                        }
                    }
                },
                2 => { // update
                    try rpc.rename(file_uuid, cli.positionals[1]);
                },
                else => unreachable,
            }
        },

        .tags => |verb| {
            if (cli.positionals.len > 1) {
                logger.err("tags only accepts a single filter option!", .{});
                return 1;
            }

            const filter: ?[]const u8 = if (cli.positionals.len > 0) cli.positionals[0] else null;

            var tag_list = rpc.listTags(global_allocator, filter, verb.count) catch |err| {
                logger.err("failed to list tags: {s}", .{@errorName(err)});
                return 1;
            };
            defer RpcClient.free(global_allocator, @TypeOf(tag_list), &tag_list);

            if (cli.options.json) {
                try std.json.stringify(tag_list, .{}, stdout);
            } else {
                //  Count |               Tag
                // -------+-----------------------------------
                //     1  | text/plain
                //     1  | image/png

                const column_header = "{s: >6} | {s: ^30}\n";
                const column_header2 = "-------+-----------------------------------";
                const column_format = "{d: >6} | {s: <30}\n";

                try stdout.print(column_header, .{
                    "Count",
                    "Tag",
                });
                try stdout.writeAll(column_header2 ++ "\r\n");

                for (tag_list) |item| {
                    try stdout.print(column_format, .{
                        item.count,
                        item.tag,
                    });
                }
            }
        },

        .gc => {
            try rpc.collectGarbage();
        },

        .help => unreachable, // we already checked for this at the start
    }

    return 0;
}

const FileEntry = struct {
    uuid: []const u8,
    user_name: ?[]const u8,
    last_change: []const u8,
};
fn renderFileList(list_items: []const RpcClient.defs.FileListItem, json: bool) !void {
    const column_header = "{s:_^36}_._{s:_^19}_._{s:_^59}\n";
    const column_format = "{s: <36} | {s: <19} | {s: <59}\n";

    var stdout = std.io.getStdOut().writer();

    var first = true;
    if (json) {
        try stdout.writeAll("[");
    } else {
        try stdout.print(column_header, .{
            "UUID",
            "Last Change",
            "File Name",
        });
    }
    //________________UUID_________________._____Last Change_____.__________________________File Name_________________________
    //17f2bde8-9d71-4ceb-93f9-1cb63cc4633e | 2021-08-29 15:50:21 | Das kleine Handbuch für angehende Raumfahrer
    //f055ec50-5570-4f9b-9b88-671b81cd62cf | 2021-08-29 15:50:21 | Donnerwetter
    for (list_items) |item| {
        if (json) {
            defer first = false;
            if (!first)
                try stdout.writeAll(",");
            try std.json.stringify(item, .{}, stdout);
        } else {
            try stdout.print(column_format, .{
                item.uuid,
                item.last_change,
                item.user_name,
            });
        }
    }
    if (json) {
        try stdout.writeAll("]\n");
    }
}

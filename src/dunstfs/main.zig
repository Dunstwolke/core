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
        \\  add <path> [--mime <type>] [tag] [tag] [tag] ...
        \\    Adds a new file at <path> to the DunstFS and adds all additional tags to it.
        \\    Will automatically add a mime type tag if it can be detected via `file --brief --mime-type` as
        \\    well as a date tag for the creation date.
        \\    Will output the file guid to stdout.
        \\    This action fails when the file is already existent (determined by its hash)
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
        \\  rm <guid>
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
const args_parser = @import("args");
const sqlite3 = @import("sqlite3");
const known_folders = @import("known-folders");
const Uuid = @import("uuid6");

const logger = std.log.scoped(.dfs);

// Set the log level to warning
pub const log_level: std.log.Level = if (std.builtin.mode == .Debug) std.log.Level.debug else std.log.Level.info;

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

    const EmptyOptions = struct {};

    const HelpOptions = EmptyOptions;
    const AddOptions = struct {
        mime: ?[]const u8 = null,
    };
    const LsOptions = struct {
        count: u32 = 25,

        pub const shorthands = .{
            .c = "count",
        };
    };
    const TagOptions = EmptyOptions;
    const RmOptions = EmptyOptions;
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
    const NameOptions = EmptyOptions;
    const FindOptions = struct {
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
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = &gpa.allocator;

const version = struct {
    const major = 0;
    const minor = 1;
    const patch = 0;
};

pub fn main() !u8 {
    defer _ = gpa.deinit();

    var cli = args_parser.parseWithVerbForCurrentProcess(CommonOptions, Verb, global_allocator, .print) catch return 1;
    defer cli.deinit();

    var stdout = std.io.getStdOut().writer();

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

    logger.info("Initialize PRNG...", .{});
    var rng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));

    logger.info("Initialize UUID source...", .{});
    const source = Uuid.v4.Source.init(&rng.random);

    logger.info("Clone working directory...", .{});
    var working_directory = try std.fs.cwd().openDir(".", .{});
    defer working_directory.close();

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

    // meh. sqlite needs this (still), though
    try root_dir.setAsCwd();

    if (cli.options.verbose) {
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var path = try std.fs.realpath(".", &buffer);
        logger.info("Data directory is '{s}'", .{path});
    }

    logger.info("Opening sqlite3 databse...", .{});
    var db = try sqlite3.Db.init(.{
        .mode = .{ .File = "storage.db3" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
    });
    defer db.deinit();

    logger.info("Initialize database...", .{});
    inline for (prepared_statement_sources.init_statements) |code| {
        var init_db_stmt = db.prepare(code) catch |err| {
            std.debug.print("error while executing sql:\n{s}\n", .{code});
            return err;
        };
        defer init_db_stmt.deinit();

        try init_db_stmt.exec(.{}, .{});
    }

    logger.info("Begin processing verb '{s}'...", .{std.meta.tagName(cli.verb.?)});

    _ = source;

    var arena = std.heap.ArenaAllocator.init(global_allocator);
    defer arena.deinit();

    switch (cli.verb.?) {
        .add => |verb| {
            logger.err("'add' not implemented yet. verb data: {}", .{verb});
        },
        .ls => |verb| {
            var diag = sqlite3.Diagnostics{};
            errdefer std.log.err("sqlite failed: {}", .{diag});

            const query_text = blk: {
                var builder = std.ArrayList(u8).init(&arena.allocator);
                defer builder.deinit();

                const writer = builder.writer();

                try writer.writeAll(
                    \\SELECT
                    \\    Files.uuid,
                    \\    Files.user_name,
                    \\    Files.last_change 
                    \\  FROM Files
                    \\  INNER JOIN FileTags ON Files.uuid = FileTags.file 
                );
                if (cli.positionals.len > 0) {
                    try writer.writeAll(
                        \\
                        \\  WHERE
                    );

                    for (cli.positionals) |tag_filter, i| {
                        if (i > 0) {
                            try writer.writeAll("\n   AND ");
                        } else {
                            try writer.writeAll("\n       ");
                        }
                        var tag = tag_filter;
                        if (std.mem.startsWith(u8, tag_filter, "-")) {
                            try writer.writeAll("NOT ");
                            tag = tag_filter[1..];
                        }
                        // TODO: Transform tag filter here
                        try writer.print("(FileTags.tag LIKE '{s}')", .{tag});
                    }
                }

                try writer.writeAll(
                    \\
                    \\  GROUP BY Files.uuid, Files.user_name, Files.last_change
                    \\  ORDER BY last_change DESC 
                    \\  LIMIT :count
                );

                break :blk builder.toOwnedSlice();
            };
            _ = verb;

            std.debug.print("query:\n{s}\n", .{query_text});

            var query = try db.prepareDynamic(query_text);
            defer query.deinit();

            var iter = try query.iterator(FileEntry, .{ .count = verb.count });

            try renderFileList(&arena.allocator, &iter, cli.options.json);
        },
        .tag => |verb| {
            logger.err("'tag' not implemented yet. verb data: {}", .{verb});
        },
        .rm => |verb| {
            logger.err("'rm' not implemented yet. verb data: {}", .{verb});
        },
        .get => |verb| {
            logger.err("'get' not implemented yet. verb data: {}", .{verb});
        },
        .update => |verb| {
            logger.err("'update' not implemented yet. verb data: {}", .{verb});
        },
        .info => |verb| {
            logger.err("'info' not implemented yet. verb data: {}", .{verb});
        },
        .name => |verb| {
            logger.err("'name' not implemented yet. verb data: {}", .{verb});
        },
        .find => |verb| {
            if (cli.positionals.len != 1) {
                logger.err("find requires a search option!", .{});
                return 1;
            }

            var diag = sqlite3.Diagnostics{};
            errdefer std.log.err("sqlite failed: {}", .{diag});

            var query = try db.prepare(
                \\SELECT * FROM Files WHERE user_name LIKE ?{text} ORDER BY user_name LIMIT ?{u32}
            );
            defer query.deinit();

            const real_limit: u32 = verb.count orelse std.math.maxInt(u32);

            var real_filter = sqlite3.Text{ .data = cli.positionals[0] };
            if (!verb.exact) {
                real_filter.data = try std.fmt.allocPrint(&arena.allocator, "%{s}%", .{real_filter.data});
            }

            var iter = try query.iterator(FileEntry, .{ .filter = real_filter, .limit = real_limit });

            try renderFileList(&arena.allocator, &iter, cli.options.json);
        },
        .tags => |verb| {
            if (cli.positionals.len > 1) {
                logger.err("tags only accepts a single filter option!", .{});
                return 1;
            }

            var diag = sqlite3.Diagnostics{};
            errdefer std.log.err("sqlite failed: {}", .{diag});

            var query = try db.prepare(
                \\SELECT * FROM Tags WHERE tag LIKE ?{text} ORDER BY count LIMIT ?{u32}
            );
            defer query.deinit();

            const Entry = struct {
                tag: []const u8,
                count: u32,
            };

            const column_header = "{s:_>6}_._{s:_^30}\n";
            const column_format = "{d: >6} | {s: <30}\n";

            const real_limit: u32 = verb.count orelse std.math.maxInt(u32);
            const real_filter = sqlite3.Text{ .data = if (cli.positionals.len > 0) cli.positionals[0] else "%" };

            var iter = try query.iterator(Entry, .{ .filter = real_filter, .limit = real_limit });
            var first = true;
            if (cli.options.json) {
                try stdout.writeAll("[");
            } else {
                try stdout.print(column_header, .{
                    "Count",
                    "Tag",
                });
            }

            // _Count_.______________Tag______________
            //     1 | text/plain
            //     1 | image/png
            while (try iter.next(.{ .diags = null, .allocator = &arena.allocator })) |item| {
                if (cli.options.json) {
                    defer first = false;
                    if (!first)
                        try stdout.writeAll(",");
                    try std.json.stringify(item, .{}, stdout);
                } else {
                    try stdout.print(column_format, .{
                        item.count,
                        item.tag,
                    });
                }
            }
            if (cli.options.json) {
                try stdout.writeAll("]\n");
            }
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
fn renderFileList(allocator: *std.mem.Allocator, iter: anytype, json: bool) !void {
    if (@typeInfo(@TypeOf(iter)) != .Pointer) @compileError("iter must be a pointer!");

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
    while (try iter.next(.{ .diags = null, .allocator = allocator })) |item| {
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
};

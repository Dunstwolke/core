//! DunstFS experimental implementation and command line client.
//! 
//! Planned features:
//! - Search the DFS
//! - Add files
//! - RMW files (move to temp, open with editor, write back and update checksum)
//!
//!

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
        \\  ls [tag] [-tag] [tag] ...
        \\    Lists the last 25 files that matches the tag filters. Tags can use wildcards here
        \\    to filter out files that are not of interest. Tags prefixed with - will be excluded
        \\    the result set.
        \\    Files will be listed newest-to-oldest so it's easier to find actively used files again.
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
        \\  find <hname>
        \\    Finds files based on their human readable name. Allows globbing on <hname>.
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

    const EmptyOptions = struct {};

    const HelpOptions = EmptyOptions;
    const AddOptions = struct {
        mime: ?[]const u8 = null,
    };
    const LsOptions = EmptyOptions;
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
    const FindOptions = EmptyOptions;
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

    // Do opt early out when invoking help command, as we don't need to initialize anything here.
    if (cli.options.help or (cli.verb == null) or (cli.verb.? == .help)) {
        try printUsage(std.io.getStdOut().writer());
        return 0;
    }

    if (cli.options.version) {
        var stdout = std.io.getStdOut().writer();
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

    if (current_log_level == .debug) {
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

    switch (cli.verb.?) {
        .add => |verb| {
            logger.err("'add' not implemented yet. verb data: {}", .{verb});
        },
        .ls => |verb| {
            logger.err("'ls' not implemented yet. verb data: {}", .{verb});
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
            logger.err("'find' not implemented yet. verb data: {}", .{verb});
        },

        .help => unreachable, // we already checked for this at the start
    }

    return 1;
}

const prepared_statement_sources = struct {
    const init_statements = [_][]const u8{
        \\CREATE TABLE IF NOT EXISTS Files (
        \\  uuid TEXT PRIMARY KEY NOT NULL, -- a UUIDv4 that is used as a unique identifier
        \\  user_name TEXT NULL             -- A text that was given by the user as a human-readable name
        \\);
        ,
        \\CREATE TABLE IF NOT EXISTS DataSets (
        \\  uuid TEXT NOT NULL,             -- The key of the file
        \\  revision INT NOT NULL,          -- Ever-increasing revision number of the file. The biggest number is the latest revision.
        \\  checksum TEXT NOT NULL,         -- SHA1 of the file contents
        \\  mime_type TEXT NOT NULL,        -- The mime type
        \\  creation_date TEXT NOT NULL     -- ISO timestamp of when the file was created
        \\);
        ,
        \\CREATE TABLE IF NOT EXISTS FileTags (
        \\  file TEXT NOT NULL,             -- The key of the file
        \\  tag TEXT NOT NULL,              -- The tag name
        \\  UNIQUE(file,tag)
        \\);
        ,
        \\CREATE VIEW IF NOT EXISTS Tags AS SELECT tag, COUNT(file) AS count FROM FileTags GROUP BY tag
    };
};

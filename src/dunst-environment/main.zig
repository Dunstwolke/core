const std = @import("std");
const known_folders = @import("known-folders");
const logger = std.log.scoped(.dunst_environment);

pub const RootFolder = enum {
    /// Used by DunstFS filesystem to store datasets and metadata
    filesystem,

    /// Operating system applications are stored here
    bin,

    /// This folder stores configuration files or folders for Dunstwolke services
    config,
};

pub fn openRoot(folder: RootFolder, options: std.fs.Dir.OpenDirOptions) !std.fs.Dir {
    var data_dir = try openDunstRoot();
    defer data_dir.close();

    return data_dir.makeOpenPath(@tagName(folder), options) catch |err| {
        logger.err("Could not open the Dunstwolke directory '/{s}': {s}", .{ @tagName(folder), @errorName(err) });
        return err;
    };
}

fn openDunstRoot() !std.fs.Dir {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    if (std.process.getEnvVarOwned(arena.allocator(), "DUNSTWOLKE_ROOT_FS")) |dunstwolke_root_fs| {
        if (std.mem.trim(u8, dunstwolke_root_fs, " \r\n\t").len > 0) {
            if (!std.fs.path.isAbsolute(dunstwolke_root_fs)) {
                logger.err("Environment variable DUNSTWOLKE_ROOT_FS must be an absolute path!", .{});
                return error.InvalidEnvVariable;
            }
            return try std.fs.openDirAbsolute(dunstwolke_root_fs, .{});
        }
    } else |_| {
        // ignore the error
    }

    const maybe_data_dir = known_folders.open(arena.allocator(), .data, .{}) catch |err| {
        logger.err(" nCouldot open the data directory: {s}", .{@errorName(err)});
        return err;
    };
    var data_dir = maybe_data_dir orelse {
        logger.err("Could not find the data directory!", .{});
        return error.FileNotFound;
    };
    defer data_dir.close();

    return data_dir.makeOpenPath("dunstwolke", .{}) catch |err| {
        logger.err("Could not open the Dunstwolke root directory: {s}", .{@errorName(err)});
        return err;
    };
}

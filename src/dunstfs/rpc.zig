const std = @import("std");
const rpc = @import("antiphony");
const Uuid = @import("uuid6");
const network = @import("network");

pub const dunstfs_port = 5229;
pub const protocol_magic = [4]u8{ 0x42, 0x6c, 0x74, 0xb6 };
pub const protocol_version: u8 = 1;

pub const end_point = network.EndPoint{
    .address = .{ .ipv4 = network.Address.IPv4.loopback },
    .port = dunstfs_port,
};

pub const public_end_point = network.EndPoint{
    .address = .{ .ipv4 = network.Address.IPv4.any },
    .port = dunstfs_port,
};

pub const AddFileError = error{ OutOfMemory, IoError, Timeout, SourceNotFound };
pub const UpdateFileError = error{ OutOfMemory, IoError, Timeout, FileNotFound, SourceNotFound };
pub const RemoveFileError = error{ OutOfMemory, IoError, Timeout, FileNotFound };
pub const GetFileError = error{ OutOfMemory, IoError, Timeout, FileNotFound, AccessDenied };
pub const RenameFileError = error{ OutOfMemory, IoError, Timeout, FileNotFound };
pub const AddTagError = error{ OutOfMemory, IoError, Timeout, FileNotFound };
pub const RemoveTagError = error{ OutOfMemory, IoError, Timeout, FileNotFound };
pub const ListFileTagsError = error{ OutOfMemory, IoError, Timeout, FileNotFound };
pub const ListTagsError = error{ OutOfMemory, IoError, Timeout };
pub const ListFilesError = error{ OutOfMemory, IoError, Timeout };
pub const OpenFileError = error{ OutOfMemory, IoError, Timeout, FileNotFound };
pub const FileInfoError = error{ OutOfMemory, IoError, Timeout, FileNotFound };

pub const FileListItem = struct {
    uuid: Uuid,
    name: ?[]const u8,
    mime: []const u8,
};

pub const TagInfo = struct {
    tag: []const u8,
    count: u32,
};

pub const FileInfo = struct {
    // sorted new-to-old
    name: ?[]const u8,
    revisions: []const Revision,
};

pub const Revision = struct {
    hash: [32]u8, // blake3
    date: [19]u8, // YYYY-MM-DD hh:mm:ss
    mime: []const u8,
    size: u64,
};

pub const Definition = rpc.CreateDefinition(.{
    .host = .{
        // File management
        .add = fn (source_file: []const u8, mime_type: []const u8, name: ?[]const u8, tags: []const []const u8) AddFileError!Uuid,
        .update = fn (file: Uuid, source_file: []const u8, mime: []const u8) UpdateFileError!void,
        .rename = fn (file: Uuid, name: ?[]const u8) RenameFileError!void,
        .delete = fn (file: Uuid) RemoveFileError!void,
        .get = fn (file: Uuid, target: []const u8) GetFileError!void,
        .open = fn (file: Uuid, read_only: bool) OpenFileError!void,
        .info = fn (file: Uuid) FileInfoError!FileInfo,

        .list = fn (skip: u32, limit: ?u32, include_filters: []const []const u8, exclude_filters: []const []const u8) ListFilesError!FileListItem,
        .find = fn (skip: u32, limit: ?u32, filter: []const u8) ListFilesError!FileListItem,

        // Tag management
        .addTags = fn (file: Uuid, tags: []const []const u8) AddTagError!void,
        .removeTags = fn (file: Uuid, tags: []const []const u8) RemoveTagError!void,
        .listFileTags = fn (file: Uuid) ListFileTagsError![]const u8,
        .listTags = fn (filter: ?[]const u8, limit: ?u32) ListTagsError![]TagInfo,

        // Utility
        .collectGarbage = fn () void,
    },
    .client = .{},
});

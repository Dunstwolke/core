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

pub const AllocatingCall = rpc.AllocatingCall;

pub const AddFileError = error{ OutOfMemory, AccessDenied, IoError, InvalidSourceFile, SourceFileNotFound };
pub const UpdateFileError = error{ OutOfMemory, AccessDenied, IoError, InvalidSourceFile, FileNotFound, SourceFileNotFound };
pub const RemoveFileError = error{ OutOfMemory, IoError, FileNotFound };
pub const GetFileError = error{ OutOfMemory, IoError, FileNotFound, AccessDenied };
pub const RenameFileError = error{ OutOfMemory, IoError, FileNotFound };
pub const AddTagError = error{ OutOfMemory, IoError, FileNotFound };
pub const RemoveTagError = error{ OutOfMemory, IoError, FileNotFound };
pub const ListFileTagsError = error{ OutOfMemory, IoError, FileNotFound };
pub const ListTagsError = error{ OutOfMemory, IoError };
pub const ListFilesError = error{ OutOfMemory, IoError };
pub const OpenFileError = error{ OutOfMemory, IoError, FileNotFound };
pub const FileInfoError = error{ OutOfMemory, IoError, FileNotFound };

pub const FileListItem = struct {
    uuid: Uuid,
    user_name: ?[]const u8,
    last_change: []const u8,
    mime_type: []const u8,
};

pub const TagInfo = struct {
    tag: []const u8,
    count: u32,
};

pub const Date = [19]u8; // YYYY-MM-DD hh:mm:ss

pub const FileInfo = struct {
    name: ?[]const u8,
    tags: []const []const u8,
    revisions: []const Revision, // sorted new-to-old
    last_change: Date,
};

pub const Revision = struct {
    number: u32,
    dataset: [32]u8, // blake3 hash of the file contents
    date: Date,
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

        .list = fn (skip: u32, limit: ?u32, include_filters: []const []const u8, exclude_filters: []const []const u8) ListFilesError![]FileListItem,
        .find = fn (skip: u32, limit: ?u32, filter: []const u8, exact: bool) ListFilesError![]FileListItem,

        // Tag management
        .addTags = fn (file: Uuid, tags: []const []const u8) AddTagError!void,
        .removeTags = fn (file: Uuid, tags: []const []const u8) RemoveTagError!void,
        .listFileTags = fn (file: Uuid) ListFileTagsError![]const []const u8,
        .listTags = fn (filter: ?[]const u8, limit: ?u32) ListTagsError![]TagInfo,

        // Utility
        .collectGarbage = fn () void,
    },
    .client = .{},
});

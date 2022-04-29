const std = @import("std");
const network = @import("network");
const rpc = @import("rpc.zig");
const antiphony = @import("antiphony");
const Uuid = @import("uuid6");
const logger = std.log.scoped(.rpc_client);

const RpcClientEndPoint = rpc.Definition.ClientEndPoint(network.Socket.Reader, network.Socket.Writer, ClientControl);

const ClientControl = struct {
    dummy: u8 = 0,
};
var client_ctrl = ClientControl{};

const RpcClient = @This();

socket: network.Socket,
service: RpcClientEndPoint,

pub const defs = rpc;
pub const free = RpcClientEndPoint.free;

pub const AllocatingCall = antiphony.AllocatingCall;

pub fn connect(allocator: std.mem.Allocator, host_name: ?[]const u8) !RpcClient {
    var socket = if (host_name) |host|
        try network.connectToHost(allocator, host, rpc.dunstfs_port, .tcp)
    else blk: {
        var socket = try network.Socket.create(.ipv4, .tcp);
        errdefer socket.close();

        try socket.connect(rpc.end_point);

        break :blk socket;
    };
    errdefer socket.close();

    var reader = socket.reader();
    var writer = socket.writer();

    try writer.writeAll(&rpc.protocol_magic);
    try writer.writeIntLittle(u8, rpc.protocol_version);

    var service = RpcClientEndPoint.init(allocator, reader, writer);
    errdefer service.destroy();

    try service.connect(&client_ctrl);

    return RpcClient{
        .socket = socket,
        .service = service,
    };
}

pub fn deinit(self: *RpcClient) void {
    self.service.shutdown() catch |err| {
        logger.err("failed to cleanly shut down rpc service: {s}", .{@errorName(err)});
    };
    self.socket.close();
    self.* = undefined;
}

pub fn add(self: *RpcClient, source_file: []const u8, mime_type: []const u8, name: ?[]const u8, tags: []const []const u8) !Uuid {
    return try self.service.invoke("add", .{ source_file, mime_type, name, tags });
}
pub fn update(self: *RpcClient, file: Uuid, source_file: []const u8, mime: []const u8) !void {
    return try self.service.invoke("update", .{ file, source_file, mime });
}
pub fn rename(self: *RpcClient, file: Uuid, name: ?[]const u8) !void {
    return try self.service.invoke("rename", .{ file, name });
}
pub fn delete(self: *RpcClient, file: Uuid) !void {
    return try self.service.invoke("delete", .{file});
}
pub fn get(self: *RpcClient, file: Uuid, target: []const u8) !void {
    return try self.service.invoke("get", .{ file, target });
}
pub fn open(self: *RpcClient, file: Uuid, read_only: bool) !void {
    return try self.service.invoke("open", .{ file, read_only });
}
pub fn info(self: *RpcClient, allocator: std.mem.Allocator, file: Uuid) !rpc.FileInfo {
    return try self.service.invokeAlloc(allocator, "info", .{file});
}
pub fn list(self: *RpcClient, allocator: std.mem.Allocator, skip: u32, limit: ?u32, include_filters: []const []const u8, exclude_filters: []const []const u8) ![]rpc.FileListItem {
    return try self.service.invokeAlloc(allocator, "list", .{ skip, limit, include_filters, exclude_filters });
}
pub fn find(self: *RpcClient, allocator: std.mem.Allocator, skip: u32, limit: ?u32, filter: []const u8, exact: bool) ![]rpc.FileListItem {
    return try self.service.invokeAlloc(allocator, "find", .{ skip, limit, filter, exact });
}
pub fn addTags(self: *RpcClient, file: Uuid, tags: []const []const u8) !void {
    return try self.service.invoke("addTags", .{ file, tags });
}
pub fn removeTags(self: *RpcClient, file: Uuid, tags: []const []const u8) !void {
    return try self.service.invoke("removeTags", .{ file, tags });
}
pub fn listFileTags(self: *RpcClient, allocator: std.mem.Allocator, file: Uuid) ![]const []const u8 {
    return try self.service.invokeAlloc(allocator, "listFileTags", .{file});
}
pub fn listTags(self: *RpcClient, allocator: std.mem.Allocator, filter: ?[]const u8, limit: ?u32) ![]rpc.TagInfo {
    return try self.service.invokeAlloc(allocator, "listTags", .{ filter, limit });
}
pub fn collectGarbage(self: *RpcClient) !void {
    return try self.service.invoke("collectGarbage", .{});
}

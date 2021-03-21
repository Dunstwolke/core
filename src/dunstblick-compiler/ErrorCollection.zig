const std = @import("std");

const Location = @import("Location.zig");

pub const CompileError = struct {
    where: Location,
    message: []const u8,

    pub fn format(value: @This(), fmt: []const u8, options: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.print("{}: {s}", .{
            value.where,
            value.message,
        });
    }
};

const Self = @This();

arena: std.heap.ArenaAllocator,
list: std.ArrayList(CompileError),

pub fn init(allocator: *std.mem.Allocator) Self {
    return Self{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .list = std.ArrayList(CompileError).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
    self.list.deinit();
    self.* = undefined;
}

pub fn add(self: *Self, where: Location, comptime fmt: []const u8, args: anytype) !void {
    const msg = try std.fmt.allocPrint(&self.arena.allocator, fmt, args);
    errdefer self.arena.allocator.free(msg);

    try self.list.append(CompileError{
        .where = where,
        .message = msg,
    });
}

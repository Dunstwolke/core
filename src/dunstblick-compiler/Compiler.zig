const std = @import("std");

const Self = @This();

pub const Location = @import("Location.zig");
pub const Tokenizer = @import("Tokenizer.zig");
pub const Database = @import("Database.zig");
pub const Parser = @import("Parser.zig");
pub const ErrorCollection = @import("ErrorCollection.zig");

allocator: std.mem.Allocator,
database: *Database,

errors: ErrorCollection,

pub fn init(allocator: std.mem.Allocator, database: *Database) Self {
    return Self{
        .allocator = allocator,
        .database = database,
        .errors = ErrorCollection.init(allocator),
    };
}
pub fn deinit(self: *Self) void {
    self.errors.deinit();
    self.* = undefined;
}

pub fn compile(self: *Self, reader: anytype, writer: anytype) !void {
    var input_src = std.ArrayList(u8).init(self.allocator);
    defer input_src.deinit();

    try reader.readAllArrayList(&input_src, 4 << 20);

    var tokenIterator = Tokenizer.init(input_src.items);

    var parser = Parser{
        .allocator = self.allocator,
        .database = self.database,

        .errors = &self.errors,
        .tokens = &tokenIterator,
    };

    parser.parseFile(writer) catch |err| {
        try self.errors.add(tokenIterator.location, "syntax error: {s}", .{
            err,
        });
        return err;
    };
}

pub fn getErrors(self: Self) []const ErrorCollection.CompileError {
    return self.errors.list.items;
}

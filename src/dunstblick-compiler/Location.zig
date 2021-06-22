const std = @import("std");

line: u32,
column: u32,

pub fn format(value: @This(), fmt: []const u8, options: std.fmt.FormatOptions, stream: anytype) !void {
    _ = fmt;
    _ = options;
    try stream.print("{d}:{d}", .{
        value.line,
        value.column,
    });
}

const std = @import("std");

usingnamespace @import("types.zig");
usingnamespace @import("object.zig");
usingnamespace @import("widget.zig");

pub fn main() anyerror!void {
    const allocator = std.heap.direct_allocator;

    var context = UIContext.init(allocator);
    defer context.deinit();

    context.root = Widget.init(&context, .panel);

    std.debug.warn("All your base are belong to us.\n", .{});
}

const std = @import("std");

usingnamespace @import("types.zig");
usingnamespace @import("object.zig");
usingnamespace @import("widget.zig");

// TODO:
// - Remove ObjectRef/ObjectID differentiation. It's basically the same except for "resolve" function
// - 

pub fn main() anyerror!void {
    const allocator = std.heap.direct_allocator;

    var context = UIContext.init(allocator);
    defer context.deinit();

    context.root = Widget.init(&context);

    // std.meta.intToEnum

    std.debug.warn("All your base are belong to us.\n");
}

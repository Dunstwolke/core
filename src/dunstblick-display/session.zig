const cpp = @import("cpp.zig");

pub const Session = struct {
    const Self = @This();

    cpp_session: *cpp.ZigSession,

    destroy: fn (self: *Self) void,
    update: fn (self: *Self) error{OutOfMemory}!bool,
};

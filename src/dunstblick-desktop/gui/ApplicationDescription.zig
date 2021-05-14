const std = @import("std");

const Self = @This();
const ApplicationInstance = @import("ApplicationInstance.zig");

pub const Interface = struct {
    const GenericError = error{OutOfMemory};
    spawn: fn (*Self, *std.mem.Allocator) GenericError!*ApplicationInstance,

    pub fn get(comptime T: type) *const @This() {
        return &struct {
            const vtable = Interface{
                .spawn = T.spawn,
            };
        }.vtable;
    }
};

/// The name of the application that is displayed
display_name: [:0]const u8,

/// If the application has a TVG icon, this field is not null and contains the 
/// application icon
icon: ?[]const u8,

vtable: *const Interface,

/// Spawns a new instance of this application
pub fn spawn(self: *Self, allocator: *std.mem.Allocator) !*ApplicationInstance {
    return try self.vtable.spawn(self, allocator);
}

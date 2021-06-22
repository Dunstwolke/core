const std = @import("std");

const Self = @This();
const ApplicationInstance = @import("ApplicationInstance.zig");

pub const Interface = struct {
    pub const SpawnError = error{ IoError, OutOfMemory };
    pub const DestroyError = error{Indestructible};
    spawn: fn (*Self, *std.mem.Allocator) SpawnError!*ApplicationInstance,
    destroy: fn (*Self) DestroyError!void,

    pub fn get(comptime T: type) *const @This() {
        return &struct {
            fn destroyFallback(self: *Self) DestroyError!void {
                _ = self;
                return DestroyError.Indestructible;
            }

            const vtable = Interface{
                .spawn = T.spawn,
                .destroy = if (@hasDecl(T, "destroy")) T.destroy else destroyFallback,
            };
        }.vtable;
    }
};

pub const State = union(enum) {
    /// The app isn't available
    not_available,
    /// The app was there once, but is gone now. They user should delete it now
    gone,
    /// The app is ready to be started
    ready,
};

/// The name of the application that is displayed
display_name: [:0]const u8,

/// If the application has a TVG icon, this field is not null and contains the 
/// application icon
icon: ?[]const u8,

/// The VTable for the application, provides methods for this 
vtable: *const Interface,

state: State,

/// Spawns a new instance of this application
pub fn spawn(self: *Self, allocator: *std.mem.Allocator) Interface.SpawnError!*ApplicationInstance {
    return try self.vtable.spawn(self, allocator);
}

/// Destroys this application description if possible.
pub fn destroy(self: *Self) Interface.DestroyError!void {
    return try self.vtable.destroy(self);
}

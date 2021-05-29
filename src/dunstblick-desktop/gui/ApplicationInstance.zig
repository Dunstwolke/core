const std = @import("std");

const zerog = @import("zero-graphics");

const Self = @This();
const ApplicationDescription = @import("ApplicationDescription.zig");

const Size = zerog.Size;

pub const Interface = struct {
    const GenericError = error{OutOfMemory};
    update: fn (*Self, f32) GenericError!void,
    resize: fn (*Self, size: Size) GenericError!void,
    render: fn (*Self, target: *zerog.Renderer2D) GenericError!void,
    deinit: fn (*Self) void,

    pub fn get(comptime T: type) *const @This() {
        return &struct {
            const vtable = Interface{
                .update = T.update,
                .resize = T.resize,
                .render = T.render,
                .deinit = T.deinit,
            };
        }.vtable;
    }
};

pub const Status = union(enum) {
    /// contains the current loading status as a string
    starting: []const u8,

    /// the application is ready to be interacted with
    running,

    /// the application was quit and should be freed by the 
    /// desktop environment. Contains the exit reason.
    exited: []const u8,
};

description: ApplicationDescription,
vtable: *const Interface,
status: Status = Status{ .starting = "Starting..." },

pub fn update(self: *Self, dt: f32) !void {
    std.debug.assert(self.status == .starting or self.status == .running);
    try self.vtable.update(self, dt);
}

pub fn resize(self: *Self, size: Size) !void {
    std.debug.assert(self.status == .starting or self.status == .running);
    try self.vtable.resize(self, size);
}

pub fn render(self: *Self, target: *zerog.Renderer2D) !void {
    std.debug.assert(self.status == .running);
    try self.vtable.render(self, target);
}

pub fn deinit(self: *Self) void {
    self.vtable.deinit(self);
}

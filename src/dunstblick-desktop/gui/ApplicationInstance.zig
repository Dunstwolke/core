const std = @import("std");

const Self = @This();
const ApplicationDescription = @import("ApplicationDescription.zig");
const Framebuffer = @import("Framebuffer.zig");
const Size = @import("Size.zig");

pub const Interface = struct {
    const GenericError = error{OutOfMemory};
    update: fn (*Self, f32) GenericError!void,
    resize: fn (*Self, size: Size) GenericError!void,
    render: fn (*Self, target: Framebuffer) GenericError!void,
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
    ready,
};

description: ApplicationDescription,
vtable: *const Interface,
status: Status = Status{ .starting = "Starting..." },

pub fn update(self: *Self, dt: f32) !void {
    try self.vtable.update(self, dt);
}

pub fn resize(self: *Self, size: Size) !void {
    try self.vtable.resize(self, size);
}

pub fn render(self: *Self, target: Framebuffer) !void {
    try self.vtable.render(self, target);
}

pub fn deinit(self: *Self) void {
    self.vtable.deinit(self);
}

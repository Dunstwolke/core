const std = @import("std");

const zerog = @import("zero-graphics");

const Self = @This();
const ApplicationDescription = @import("ApplicationDescription.zig");

const Size = zerog.Size;

pub const Interface = struct {
    const GenericError = error{OutOfMemory};

    pub const UpdateError = GenericError || error{IoError};
    pub const ResizeError = GenericError;
    pub const RenderError = GenericError || zerog.Renderer2D.DrawError;
    pub const UiError = GenericError || error{IoError} || zerog.UserInterface.Builder.Error;

    update: ?fn (*Self, f32) UpdateError!void,
    processUserInterface: ?fn (*Self, zerog.Rectangle, zerog.UserInterface.Builder) UiError!void,
    resize: ?fn (*Self, size: Size) ResizeError!void,
    render: ?fn (*Self, zerog.Rectangle, *zerog.Renderer2D) RenderError!void,
    close: ?fn (*Self) void,
    deinit: fn (*Self) void,

    pub fn get(comptime T: type) *const @This() {
        return &struct {
            const vtable = Interface{
                .update = if (@hasDecl(T, "update")) T.update else null,
                .resize = if (@hasDecl(T, "resize")) T.resize else null,
                .render = if (@hasDecl(T, "render")) T.render else null,
                .close = if (@hasDecl(T, "render")) T.close else null,
                .deinit = T.deinit,
                .processUserInterface = if (@hasDecl(T, "processUserInterface")) T.processUserInterface else null,
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
    if (self.vtable.update) |fun| {
        try fun(self, dt);
    }
}

pub fn resize(self: *Self, size: Size) !void {
    std.debug.assert(self.status == .starting or self.status == .running);
    if (self.vtable.resize) |fun| {
        try fun(self, size);
    }
}

pub fn render(self: *Self, rectangle: zerog.Rectangle, target: *zerog.Renderer2D) !void {
    std.debug.assert(self.status == .running);
    if (self.vtable.render) |fun| {
        try fun(self, rectangle, target);
    }
}

pub fn processUserInterface(self: *Self, rectangle: zerog.Rectangle, builder: zerog.UserInterface.Builder) !void {
    std.debug.assert(self.status == .running);
    if (self.vtable.processUserInterface) |fun| {
        try fun(self, rectangle, builder);
    }
}

/// Requests the proper shutdown of the application and a transition to state `.exited`.
/// Use this when the application should be closed.
pub fn close(self: *Self) void {
    std.debug.assert(self.status == .starting or self.status == .running);
    if (self.vtable.close) |fun| {
        fun(self);
    }
}

/// Frees all resources of this instance.
pub fn deinit(self: *Self) void {
    self.vtable.deinit(self);
}

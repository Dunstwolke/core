const std = @import("std");
const zero_graphics = @import("zero-graphics");

const ApplicationInstance = @import("../gui/ApplicationInstance.zig");
const ApplicationDescription = @import("../gui/ApplicationDescription.zig");

const Size = zero_graphics.Size;

const Self = @This();

instance: ApplicationInstance,
allocator: *std.mem.Allocator,
arena: std.heap.ArenaAllocator,

pub fn init(allocator: *std.mem.Allocator, desc: *const ApplicationDescription) !*Self {
    const app = try allocator.create(Self);
    app.* = Self{
        .instance = ApplicationInstance{
            .description = desc.*,
            .vtable = ApplicationInstance.Interface.get(Self),
        },
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
    app.instance.description.display_name = try app.arena.allocator.dupeZ(u8, app.instance.description.display_name);
    if (app.instance.description.icon) |*icon| {
        icon.* = try app.arena.allocator.dupe(u8, icon.*);
    }
    return app;
}

pub fn update(instance: *ApplicationInstance, dt: f32) !void {
    const self = @fieldParentPtr(Self, "instance", instance);
}

pub fn resize(instance: *ApplicationInstance, size: Size) !void {
    const self = @fieldParentPtr(Self, "instance", instance);

    
}

pub fn render(instance: *ApplicationInstance, rectangle: zero_graphics.Rectangle, painter: *zero_graphics.Renderer2D) !void {
    const self = @fieldParentPtr(Self, "instance", instance);
}

pub fn close(instance: *ApplicationInstance) void {
    const self = @fieldParentPtr(Self, "instance", instance);
    self.instance.status = .{ .exited = "DE killed me" };
}

pub fn deinit(instance: *ApplicationInstance) void {
    const self = @fieldParentPtr(Self, "instance", instance);
    self.arena.deinit();
    self.allocator.destroy(self);
}

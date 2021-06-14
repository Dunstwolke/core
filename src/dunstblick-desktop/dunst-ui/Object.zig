const std = @import("std");
const protocol = @import("dunstblick-protocol");

const logger = std.log.scoped(.dunstblick_object);

const types = @import("types.zig");

const Value = types.Value;
const ObjectList = types.ObjectList;

const Object = @This();

allocator: *std.mem.Allocator,
properties: std.AutoArrayHashMapUnmanaged(protocol.PropertyName, Value),

pub fn init(allocator: *std.mem.Allocator) Object {
    return Object{
        .allocator = allocator,
        .properties = .{},
    };
}

pub fn deinit(self: *Object) void {
    {
        var it = self.properties.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
    }
    self.properties.deinit(self.allocator);
    self.* = undefined;
}

/// Adds a property. If the property already exists, returns `error.AlreadyExists`.
pub fn addProperty(self: *Object, name: protocol.PropertyName, value: Value) !void {
    const gop = try self.properties.getOrPut(self.allocator, name);
    if (gop.found_existing)
        return error.AlreadyExists;

    gop.value_ptr.* = value;
}

/// Adds a property. If the property already exists, overrides the previous value.
pub fn setProperty(self: *Object, name: protocol.PropertyName, value: Value) !void {
    const gop = try self.properties.getOrPut(self.allocator, name);
    if (gop.found_existing) {
        gop.value_ptr.deinit();
    }
    gop.value_ptr.* = value;
}

pub fn getProperty(self: *Object, name: protocol.PropertyName) ?*Value {
    if (self.properties.getEntry(name)) |entry| {
        return entry.value_ptr;
    } else {
        return null;
    }
}

fn getList(self: *Object, prop_name: protocol.PropertyName) !*ObjectList {
    if (self.properties.getEntry(prop_name)) |entry| {
        if (entry.value_ptr.* == .objectlist) {
            return &entry.value_ptr.objectlist;
        } else {
            return error.TypeMismatch;
        }
    } else {
        return error.PropertyNotFound;
    }
}

pub fn clear(self: *Object, prop_name: protocol.PropertyName) !void {
    const list = try self.getList(prop_name);
    @panic("not implemented yet!");
}

pub fn insertRange(self: *Object, prop_name: protocol.PropertyName, index: usize, items: []const protocol.ObjectID) !void {
    const list = try self.getList(prop_name);
    @panic("not implemented yet!");
}

pub fn removeRange(self: *Object, prop_name: protocol.PropertyName, index: usize, count: usize) !void {
    const list = try self.getList(prop_name);
    @panic("not implemented yet!");
}

pub fn moveRange(self: *Object, prop_name: protocol.PropertyName, index_from: usize, index_to: usize, count: usize) !void {
    const list = try self.getList(prop_name);
    @panic("not implemented yet!");
}

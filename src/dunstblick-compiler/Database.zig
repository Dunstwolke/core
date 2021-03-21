const std = @import("std");

const Self = @This();
const IDMap = std.StringHashMap(u32);

pub const Entry = enum {
    resource,
    event,
    variable,
    object,
    widget,
};

arena: std.heap.ArenaAllocator,
allow_new_items: bool,

resources: IDMap,
events: IDMap,
variables: IDMap,
objects: IDMap,
widgets: IDMap,

/// Initializes a new database.
/// - `allocator` will be used to do Database-local allocations.
/// - `allow_new_items` declares that the database is allowed to insert new IDs on a call to `get` instead of returning `null`.
pub fn init(allocator: *std.mem.Allocator, allow_new_items: bool) Self {
    return Self{
        .arena = std.heap.ArenaAllocator.init(allocator),

        .allow_new_items = allow_new_items,

        .resources = IDMap.init(allocator),
        .events = IDMap.init(allocator),
        .variables = IDMap.init(allocator),
        .objects = IDMap.init(allocator),
        .widgets = IDMap.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.resources.deinit();
    self.events.deinit();
    self.variables.deinit();
    self.objects.deinit();
    self.widgets.deinit();
    self.arena.deinit();
}

pub fn get(self: *Self, kind: Entry, name: []const u8) !?u32 {
    var map: *IDMap = switch (kind) {
        .resource => &self.resources,
        .event => &self.events,
        .variable => &self.variables,
        .object => &self.objects,
        .widget => &self.widgets,
    };
    if (self.allow_new_items) {
        const gop = try map.getOrPut(name);
        if (!gop.found_existing) {
            gop.entry.value = 1; // Start incrementing from one
            var iter = map.iterator();
            while (iter.next()) |item| {
                if (gop.entry.value <= item.value) {
                    gop.entry.value = item.value + 1;
                }
            }
        }
        return gop.entry.value;
    } else {
        return map.get(name);
    }
}

/// Loads a new database from a json file.
/// - `allocator` will be used to do both function local as well as Database-local allocations.
/// - `allow_new_items` is the same as in `init()`
/// - `json` is the json document that should be loaded
pub fn fromJson(allocator: *std.mem.Allocator, allow_new_items: bool, json: []const u8) !Self {
    // don't copy as the memory is valid as long as the parse tree is valid
    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();

    var config = parser.parse(json) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidJson,
    };
    defer config.deinit();

    validateConfig(config) catch return error.InvalidJsonDocument;

    var db = init(allocator, allow_new_items);
    errdefer db.deinit();

    try db.loadIdMap(config, "resources", &db.resources);
    try db.loadIdMap(config, "callbacks", &db.events);
    try db.loadIdMap(config, "properties", &db.variables);
    try db.loadIdMap(config, "objects", &db.objects);
    try db.loadIdMap(config, "widgets", &db.widgets);

    return db;
}

fn dupe(self: *Self, str: []const u8) ![]u8 {
    return self.arena.allocator.dupe(u8, str);
}

fn loadIdMap(self: *Self, config: std.json.ValueTree, key: []const u8, map: *IDMap) !void {
    if (config.root.Object.get(key)) |value| {
        var items = value.Object.iterator();
        while (items.next()) |kv| {
            try map.put(try self.dupe(kv.key), @intCast(u32, kv.value.Integer));
        }
    }
}

fn validateObjectMap(list: std.json.Value) !void {
    if (list != .Object)
        return error.InvalidConfig;
    var iter = list.Object.iterator();
    while (iter.next()) |kv| {
        if (kv.value != .Integer)
            return error.InvalidConfig;
    }
}

fn validateConfig(config: std.json.ValueTree) !void {
    const root = config.root;
    if (root != .Object)
        return error.InvalidConfig;

    if (root.Object.get("resources")) |value| {
        try validateObjectMap(value);
    }
    if (root.Object.get("properties")) |value| {
        try validateObjectMap(value);
    }
    if (root.Object.get("callbacks")) |value| {
        try validateObjectMap(value);
    }
    if (root.Object.get("objects")) |value| {
        try validateObjectMap(value);
    }
    if (root.Object.get("widgets")) |value| {
        try validateObjectMap(value);
    }
}

const std = @import("std");
usingnamespace @import("types.zig");

pub const Object = struct {
    pub const Property = struct {
        @"type": Type,
        value: Value,
    };

    id: ObjectID,
    properties: std.AutoHashMap(PropertyID, Property),

    pub fn init(allocator: *std.mem.Allocator, id: ObjectID) Object {
        return Object{
            .id = id,
            .properties = std.AutoHashMap(PropertyID, Object.Property).init(allocator),
        };
    }

    pub fn deinit(obj: Object) void {
        obj.properties.deinit();
    }

    /// Sets a property on this object. If the property didn't exist,
    /// it initializes the property with the type of the value. If the
    /// property did already exist, it will perform a type check and
    /// return `error.TypeMismatch` when the type of `value` doesn't
    /// fit the property type.
    pub fn setProperty(obj: *Object, property: PropertyID, value: Value) !void {
        const res = try obj.properties.getOrPut(property);
        if (res.found_existing) {
            if (res.kv.value.@"type" != value)
                return error.TypeMismatch;
            res.kv.value.value = value;
        } else {
            res.kv.value = Property{
                .@"type" = value,
                .value = value,
            };
        }
    }

    /// Gets a property value or returns `null` if the property
    /// does not exist.
    pub fn getProperty(obj: Object, property: PropertyID) ?Value {
        if (obj.properties.get(property)) |kv| {
            return kv.value.value;
        } else {
            return null;
        }
    }

    /// Gets a property type or returns `null` if the property
    /// does not exist.
    pub fn getPropertyType(obj: Object, property: PropertyID) ?Type {
        if (obj.properties.get(property)) |kv| {
            return kv.value.@"type";
        } else {
            return null;
        }
    }
};

test "Object" {
    var obj = Object.init(std.heap.direct_allocator, ObjectID.init(1));
    defer obj.deinit();

    std.testing.expectEqual(@as(u32, 1), obj.id.value);

    try obj.setProperty(PropertyID.init(10), Value{ .integer = 10 });
    std.testing.expectError(error.TypeMismatch, obj.setProperty(PropertyID.init(10), Value{ .number = 10 }));
    try obj.setProperty(PropertyID.init(10), Value{ .integer = 15 });

    std.testing.expectEqual(obj.getProperty(PropertyID.init(10)), @as(?Value, Value{ .integer = 15 }));
}

pub const ObjectStore = struct {
    allocator: *std.mem.Allocator,
    objects: std.AutoHashMap(ObjectID, Object),

    pub fn init(allocator: *std.mem.Allocator) ObjectStore {
        return ObjectStore{
            .allocator = allocator,
            .objects = std.AutoHashMap(ObjectID, Object).init(allocator),
        };
    }

    pub fn deinit(store: ObjectStore) void {
        var it = store.objects.iterator();
        while (it.next()) |kv| {
            kv.value.deinit();
        }
        store.objects.deinit();
    }

    /// Gets or adds a freshly initialized object with the given id.
    pub fn addOrGet(store: *ObjectStore, id: ObjectID) !*Object {
        const res = try store.objects.getOrPut(id);
        if (!res.found_existing) {
            res.kv.value = Object.init(store.allocator, id);
        }
        std.debug.assert(res.kv.value.id.eql(id));
        return &res.kv.value;
    }

    /// Adds or replaces an object in the storage.
    pub fn addOrUpdate(store: *ObjectStore, obj: Object) !*Object {
        const res = try store.objects.getOrPut(obj.id);
        if (res.found_existing) {
            res.kv.value.deinit();
        }
        res.kv.value = obj;
        return &res.kv.value;
    }

    /// Removes an object from the store.
    pub fn remove(store: *ObjectStore, id: ObjectID) void {
        if (store.objects.remove(id)) |kv| {
            kv.value.deinit();
        }
    }

    /// Gets an object or returns null.
    pub fn get(store: ObjectStore, id: ObjectID) ?*Object {
        if (store.objects.get(id)) |kv| {
            return &kv.value;
        } else {
            return null;
        }
    }
};

test "ObjectStore" {
    var store = ObjectStore.init(std.heap.direct_allocator);
    defer store.deinit();

    const added = blk: {
        var obj = Object.init(std.heap.direct_allocator, ObjectID.init(1));
        errdefer obj.deinit();

        try obj.setProperty(PropertyID.init(10), Value{ .integer = 10 });

        break :blk try store.addOrUpdate(obj);
    };

    std.testing.expect(added == try store.addOrGet(ObjectID.init(1)));

    _ = store.get(ObjectID.init(1));

    // std.testing.expect(store.get(1) != null);
    store.remove(ObjectID.init(1));
    // std.testing.expect(store.get(1) == null);

    const fresh = try store.addOrGet(ObjectID.init(2));
    std.testing.expect(fresh == try store.addOrGet(ObjectID.init(2)));
}

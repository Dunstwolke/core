const c = @import("c.zig");
const std = @import("std");

usingnamespace @import("dunstblick.zig");

const DUNSTBLICK_DEFAULT_PORT = 1309;
const DUNSTBLICK_MULTICAST_GROUP = xnet.Address.IPv4.init(224, 0, 0, 1);
const DUNSTBLICK_MAX_APP_NAME_LENGTH = 64;

const DisconnectReason = c.dunstblick_DisconnectReason;
const ClientCapabilities = c.dunstblick_ClientCapabilities;
const Size = c.dunstblick_Size;
const ResourceID = c.dunstblick_ResourceID;
const ObjectID = c.dunstblick_ObjectID;
const EventID = c.dunstblick_EventID;
const NativeErrorCode = c.dunstblick_Error;
const PropertyName = c.dunstblick_PropertyName;
const Value = c.dunstblick_Value;
const ResourceKind = c.dunstblick_ResourceKind;

// C function pointers are actually optional:
// We remove the optional field here to make that explicit in later
// code
const EventCallback = std.meta.Child(c.dunstblick_EventCallback);
const PropertyChangedCallback = std.meta.Child(c.dunstblick_PropertyChangedCallback);
const DisconnectedCallback = std.meta.Child(c.dunstblick_DisconnectedCallback);
const ConnectedCallback = std.meta.Child(c.dunstblick_ConnectedCallback);

fn mapDunstblickError(err: DunstblickError) NativeErrorCode {
    return switch (err) {
        error.OutOfMemory => .DUNSTBLICK_ERROR_OUT_OF_MEMORY,
        error.NetworkError => .DUNSTBLICK_ERROR_NETWORK,
        error.OutOfRange => .DUNSTBLICK_ERROR_ARGUMENT_OUT_OF_RANGE,
        error.EndOfStream => .DUNSTBLICK_ERROR_NETWORK,
    };
}

fn mapDunstblickErrorVoid(value: DunstblickError!void) NativeErrorCode {
    value catch |err| return mapDunstblickError(err);
    return .DUNSTBLICK_ERROR_NONE;
}

// /*******************************************************************************
//  * Provider Implementation *
//  *******************************************************************************/
export fn dunstblick_OpenProvider(discoveryName: [*:0]const u8) callconv(.C) ?*dunstblick_Provider {
    const H = struct {
        inline fn open(dname: []const u8) !*dunstblick_Provider {
            const allocator = std.heap.c_allocator;

            const provider = try allocator.create(dunstblick_Provider);
            errdefer allocator.destroy(provider);

            provider.* = try dunstblick_Provider.init(allocator, dname);

            return provider;
        }
    };

    const name = std.mem.span(discoveryName);
    if (name.len > DUNSTBLICK_MAX_APP_NAME_LENGTH)
        return null;

    return H.open(name) catch return null;
}

export fn dunstblick_CloseProvider(provider: *dunstblick_Provider) callconv(.C) void {
    provider.close();
    provider.allocator.destroy(provider);
}

export fn dunstblick_PumpEvents(provider: *dunstblick_Provider) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    return mapDunstblickErrorVoid(provider.pumpEvents(10 * std.time.microsecond));
}

export fn dunstblick_WaitEvents(provider: *dunstblick_Provider) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    return mapDunstblickErrorVoid(provider.pumpEvents(null));
}

export fn dunstblick_SetConnectedCallback(provider: *dunstblick_Provider, callback: ?ConnectedCallback, userData: ?*c_void) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    provider.onConnected = .{ .function = callback, .user_data = userData };
    return .DUNSTBLICK_ERROR_NONE;
}

export fn dunstblick_SetDisconnectedCallback(provider: *dunstblick_Provider, callback: ?DisconnectedCallback, userData: ?*c_void) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    provider.onDisconnected = .{ .function = callback, .user_data = userData };
    return .DUNSTBLICK_ERROR_NONE;
}

export fn dunstblick_AddResource(provider: *dunstblick_Provider, resourceID: ResourceID, kind: ResourceKind, data: *const c_void, length: usize) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(provider.addResource(resourceID, kind, @ptrCast([*]const u8, data)[0..length]));
}

export fn dunstblick_RemoveResource(provider: *dunstblick_Provider, resourceID: ResourceID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(provider.removeResource(resourceID));
}

// *******************************************************************************
//  Connection Implementation *
// *******************************************************************************

export fn dunstblick_CloseConnection(connection: *dunstblick_Connection, reason: ?[*:0]const u8) void {
    const actual_reason = if (reason) |r| std.mem.span(r) else "The provider closed the connection.";

    connection.close(actual_reason);
}

export fn dunstblick_GetClientName(connection: *dunstblick_Connection) callconv(.C) [*:0]const u8 {
    return connection.header.?.clientName;
}

export fn dunstblick_GetDisplaySize(connection: *dunstblick_Connection) callconv(.C) Size {
    const lock = connection.mutex.acquire();
    defer lock.release();
    return connection.screenResolution;
}

export fn dunstblick_SetEventCallback(connection: *dunstblick_Connection, callback: EventCallback, userData: ?*c_void) callconv(.C) void {
    const lock = connection.mutex.acquire();
    defer lock.release();
    connection.onEvent = .{ .function = callback, .user_data = userData };
}

export fn dunstblick_SetPropertyChangedCallback(connection: *dunstblick_Connection, callback: PropertyChangedCallback, userData: ?*c_void) callconv(.C) void {
    const lock = connection.mutex.acquire();
    defer lock.release();
    connection.onPropertyChanged = .{ .function = callback, .user_data = userData };
}

export fn dunstblick_GetUserData(connection: *dunstblick_Connection) callconv(.C) ?*c_void {
    return connection.user_data_pointer;
}

export fn dunstblick_SetUserData(connection: *dunstblick_Connection, userData: ?*c_void) callconv(.C) void {
    connection.user_data_pointer = userData;
}

export fn dunstblick_BeginChangeObject(con: *dunstblick_Connection, id: ObjectID) callconv(.C) ?*dunstblick_Object {
    return con.beginChangeObject(id) catch null;
}

export fn dunstblick_RemoveObject(con: *dunstblick_Connection, oid: ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.removeObject(oid));
}

export fn dunstblick_SetView(con: *dunstblick_Connection, id: ResourceID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setView(id));
}

export fn dunstblick_SetRoot(con: *dunstblick_Connection, id: ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setRoot(id));
}

export fn dunstblick_SetProperty(con: *dunstblick_Connection, oid: ObjectID, name: PropertyName, value: *const Value) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setProperty(oid, name, value.*));
}

export fn dunstblick_Clear(con: *dunstblick_Connection, oid: ObjectID, name: PropertyName) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.clear(oid, name));
}

export fn dunstblick_InsertRange(con: *dunstblick_Connection, oid: ObjectID, name: PropertyName, index: u32, count: u32, values: [*]const ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.insertRange(oid, name, index, values[0..count]));
}

export fn dunstblick_RemoveRange(con: *dunstblick_Connection, oid: ObjectID, name: PropertyName, index: u32, count: u32) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.removeRange(oid, name, index, count));
}

export fn dunstblick_MoveRange(con: *dunstblick_Connection, oid: ObjectID, name: PropertyName, indexFrom: u32, indexTo: u32, count: u32) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.moveRange(oid, name, indexFrom, indexTo, count));
}

// /*******************************************************************************
//  * Object Implementation *
//  *******************************************************************************/

export fn dunstblick_SetObjectProperty(obj: *dunstblick_Object, name: PropertyName, value: *const Value) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(obj.setProperty(name, value.*));
}

export fn dunstblick_CommitObject(obj: *dunstblick_Object) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(obj.commit());
}

export fn dunstblick_CancelObject(obj: *dunstblick_Object) callconv(.C) void {
    obj.cancel();
}

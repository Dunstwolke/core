const c = @import("c.zig");
const std = @import("std");

const protocol = @import("dunstblick-protocol");

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
const Value = protocol.Value;
const ResourceKind = c.dunstblick_ResourceKind;

// C function pointers are actually optional:
// We remove the optional field here to make that explicit in later
// code
const EventCallback = std.meta.Child(c.dunstblick_EventCallback);
const PropertyChangedCallback = std.meta.Child(c.dunstblick_PropertyChangedCallback);
const DisconnectedCallback = std.meta.Child(c.dunstblick_DisconnectedCallback);
const ConnectedCallback = std.meta.Child(c.dunstblick_ConnectedCallback);

pub var log_level: std.log.Level = .err;

fn mapDunstblickError(err: DunstblickError) NativeErrorCode {
    return switch (err) {
        error.OutOfMemory => .DUNSTBLICK_ERROR_OUT_OF_MEMORY,
        error.NoSpaceLeft => .DUNSTBLICK_ERROR_OUT_OF_MEMORY,
        error.NetworkError => .DUNSTBLICK_ERROR_NETWORK,
        error.OutOfRange => .DUNSTBLICK_ERROR_ARGUMENT_OUT_OF_RANGE,
        error.EndOfStream => .DUNSTBLICK_ERROR_NETWORK,
        error.ResourceNotFound => .DUNSTBLICK_ERROR_RESOURCE_NOT_FOUND,
    };
}

fn mapDunstblickErrorVoid(value: DunstblickError!void) NativeErrorCode {
    value catch |err| return mapDunstblickError(err);
    return .DUNSTBLICK_ERROR_NONE;
}

// /*******************************************************************************
//  * Provider Implementation *
//  *******************************************************************************/
export fn dunstblick_OpenProvider(discoveryName: [*:0]const u8) callconv(.C) ?*Application {
    const H = struct {
        inline fn open(dname: []const u8) !*Application {
            const allocator = std.heap.c_allocator;

            const provider = try allocator.create(Application);
            errdefer allocator.destroy(provider);

            provider.* = try Application.init(allocator, dname);

            return provider;
        }
    };

    const name = std.mem.span(discoveryName);
    if (name.len > DUNSTBLICK_MAX_APP_NAME_LENGTH)
        return null;

    return H.open(name) catch return null;
}

export fn dunstblick_CloseProvider(provider: *Application) callconv(.C) void {
    provider.close();
    provider.allocator.destroy(provider);
}

export fn dunstblick_PumpEvents(provider: *Application) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    return mapDunstblickErrorVoid(provider.pumpEvents(10 * std.time.ms_per_s));
}

export fn dunstblick_WaitEvents(provider: *Application) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    return mapDunstblickErrorVoid(provider.pumpEvents(null));
}

export fn dunstblick_SetConnectedCallback(provider: *Application, callback: ?ConnectedCallback, userData: ?*c_void) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    provider.onConnected = .{ .function = callback, .user_data = userData };
    return .DUNSTBLICK_ERROR_NONE;
}

export fn dunstblick_SetDisconnectedCallback(provider: *Application, callback: ?DisconnectedCallback, userData: ?*c_void) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    provider.onDisconnected = .{ .function = callback, .user_data = userData };
    return .DUNSTBLICK_ERROR_NONE;
}

export fn dunstblick_AddResource(provider: *Application, resourceID: protocol.ResourceID, kind: protocol.ResourceKind, data: *const c_void, length: usize) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(provider.addResource(
        resourceID,
        kind,
        @ptrCast([*]const u8, data)[0..length],
    ));
}

export fn dunstblick_RemoveResource(provider: *Application, resourceID: protocol.ResourceID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(provider.removeResource(resourceID));
}

// *******************************************************************************
//  Connection Implementation *
// *******************************************************************************

export fn dunstblick_CloseConnection(connection: *Connection, reason: ?[*:0]const u8) void {
    const actual_reason = if (reason) |r| std.mem.span(r) else "The provider closed the connection.";

    connection.close(actual_reason);
}

export fn dunstblick_GetClientName(connection: *Connection) callconv(.C) [*:0]const u8 {
    return connection.header.?.clientName;
}

export fn dunstblick_GetDisplaySize(connection: *Connection) callconv(.C) Size {
    const lock = connection.mutex.acquire();
    defer lock.release();
    return connection.screenResolution;
}

export fn dunstblick_SetEventCallback(connection: *Connection, callback: EventCallback, userData: ?*c_void) callconv(.C) void {
    const lock = connection.mutex.acquire();
    defer lock.release();
    connection.onEvent = .{ .function = callback, .user_data = userData };
}

export fn dunstblick_SetPropertyChangedCallback(connection: *Connection, callback: PropertyChangedCallback, userData: ?*c_void) callconv(.C) void {
    const lock = connection.mutex.acquire();
    defer lock.release();
    connection.onPropertyChanged = .{ .function = callback, .user_data = userData };
}

export fn dunstblick_GetUserData(connection: *Connection) callconv(.C) ?*c_void {
    return connection.user_data_pointer;
}

export fn dunstblick_SetUserData(connection: *Connection, userData: ?*c_void) callconv(.C) void {
    connection.user_data_pointer = userData;
}

export fn dunstblick_BeginChangeObject(con: *Connection, id: protocol.ObjectID) callconv(.C) ?*Object {
    return con.beginChangeObject(id) catch null;
}

export fn dunstblick_RemoveObject(con: *Connection, oid: protocol.ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.removeObject(oid));
}

export fn dunstblick_SetView(con: *Connection, id: protocol.ResourceID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setView(id));
}

export fn dunstblick_SetRoot(con: *Connection, id: protocol.ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setRoot(id));
}

export fn dunstblick_SetProperty(con: *Connection, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const Value) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setProperty(oid, name, value.*));
}

export fn dunstblick_Clear(con: *Connection, oid: protocol.ObjectID, name: protocol.PropertyName) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.clear(oid, name));
}

export fn dunstblick_InsertRange(con: *Connection, oid: protocol.ObjectID, name: protocol.PropertyName, index: u32, count: u32, values: [*]const protocol.ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.insertRange(oid, name, index, values[0..count]));
}

export fn dunstblick_RemoveRange(con: *Connection, oid: protocol.ObjectID, name: protocol.PropertyName, index: u32, count: u32) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.removeRange(oid, name, index, count));
}

export fn dunstblick_MoveRange(con: *Connection, oid: protocol.ObjectID, name: protocol.PropertyName, indexFrom: u32, indexTo: u32, count: u32) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.moveRange(oid, name, indexFrom, indexTo, count));
}

// /*******************************************************************************
//  * Object Implementation *
//  *******************************************************************************/

export fn dunstblick_SetObjectProperty(obj: *Object, name: protocol.PropertyName, value: *const Value) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(obj.setProperty(name, value.*));
}

export fn dunstblick_CommitObject(obj: *Object) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(obj.commit());
}

export fn dunstblick_CancelObject(obj: *Object) callconv(.C) void {
    obj.cancel();
}

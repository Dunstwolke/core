const std = @import("std");

const protocol = @import("dunstblick-protocol");

const app = @import("dunstblick-app");

const DUNSTBLICK_MULTICAST_GROUP = xnet.Address.IPv4.init(224, 0, 0, 1);
const DUNSTBLICK_MAX_APP_NAME_LENGTH = 64;

const NativeErrorCode = extern enum(c_int) {
    /// The operation was successful.
    none = 0,

    /// An invalid argument was passed to the function.
    invalid_arg = 1,

    /// A network error happened.
    network = 2,

    /// An invalid type was passed to a function.
    invalid_type = 3,

    /// An argument was not in the allowed range.
    argument_out_of_range = 4,

    /// An allocation failed.
    out_of_memory = 5,

    /// A requested resource was not found.
    resource_not_found = 6,

    /// The dunstblick protocol was violated by the other host.
    protocol_violation = 7,
};

// Configure std.log
pub const log_level: std.log.Level = .err;

fn mapDunstblickError(err: app.DunstblickError) NativeErrorCode {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.NoSpaceLeft => .out_of_memory,
        error.NetworkError => .network,
        error.OutOfRange => .argument_out_of_range,
        error.EndOfStream => .network,
        error.ResourceNotFound => .resource_not_found,
        error.ProtocolViolation => .protocol_violation,
    };
}

fn mapDunstblickErrorVoid(value: app.DunstblickError!void) NativeErrorCode {
    value catch |err| return mapDunstblickError(err);
    return .none;
}

// /*******************************************************************************
//  * Provider Implementation *
//  *******************************************************************************/
export fn dunstblick_OpenProvider(
    discovery_name: [*:0]const u8,
    app_desc: ?[*:0]const u8,
    icon_ptr: ?[*]const u8,
    icon_len: usize,
) callconv(.C) ?*app.Application {
    const H = struct {
        inline fn open(
            dname: []const u8,
            app_description: ?[]const u8,
            app_icon: ?[]const u8,
        ) !*app.Application {
            const allocator = std.heap.c_allocator;

            const provider = try allocator.create(app.Application);
            errdefer allocator.destroy(provider);

            provider.* = try app.Application.open(
                allocator,
                dname,
                app_description,
                app_icon,
            );

            return provider;
        }
    };

    const name = std.mem.sliceTo(discovery_name, 0);
    if (name.len > DUNSTBLICK_MAX_APP_NAME_LENGTH)
        return null;

    return H.open(
        name,
        if (app_desc) |desc| std.mem.sliceTo(desc, 0) else null,
        if (icon_ptr != null and icon_len > 0) icon_ptr.?[0..icon_len] else null,
    ) catch return null;
}

export fn dunstblick_CloseProvider(provider: *app.Application) callconv(.C) void {
    provider.close();
    provider.allocator.destroy(provider);
}

export fn dunstblick_PumpEvents(provider: *app.Application) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    return mapDunstblickErrorVoid(provider.pumpEvents(10 * std.time.ms_per_s));
}

export fn dunstblick_WaitEvents(provider: *app.Application) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    return mapDunstblickErrorVoid(provider.pumpEvents(null));
}

export fn dunstblick_SetConnectedCallback(provider: *app.Application, callback: ?app.ConnectedCallback, userData: ?*c_void) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    provider.on_connected = .{ .function = callback, .user_data = userData };
    return .none;
}

export fn dunstblick_SetDisconnectedCallback(provider: *app.Application, callback: ?app.DisconnectedCallback, userData: ?*c_void) callconv(.C) NativeErrorCode {
    const lock = provider.mutex.acquire();
    defer lock.release();

    provider.on_disconnected = .{ .function = callback, .user_data = userData };
    return .none;
}

export fn dunstblick_AddResource(provider: *app.Application, resourceID: protocol.ResourceID, kind: protocol.ResourceKind, data: *const c_void, length: usize) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(provider.addResource(
        resourceID,
        kind,
        @ptrCast([*]const u8, data)[0..length],
    ));
}

export fn dunstblick_RemoveResource(provider: *app.Application, resourceID: protocol.ResourceID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(provider.removeResource(resourceID));
}

// *******************************************************************************
//  Connection Implementation *
// *******************************************************************************

export fn dunstblick_CloseConnection(connection: *app.Connection, reason: ?[*:0]const u8) void {
    const actual_reason = if (reason) |r| std.mem.span(r) else "The provider closed the connection.";

    connection.close(actual_reason);
}

export fn dunstblick_GetClientName(connection: *app.Connection) callconv(.C) [*:0]const u8 {
    return "unknown"; // TODO: Reintrocude client names?
}

export fn dunstblick_GetDisplaySize(connection: *app.Connection) callconv(.C) app.Size {
    const lock = connection.mutex.acquire();
    defer lock.release();
    return connection.screen_resolution;
}

export fn dunstblick_SetEventCallback(connection: *app.Connection, callback: app.EventCallback, userData: ?*c_void) callconv(.C) void {
    const lock = connection.mutex.acquire();
    defer lock.release();
    connection.on_event = .{ .function = callback, .user_data = userData };
}

export fn dunstblick_SetPropertyChangedCallback(connection: *app.Connection, callback: app.PropertyChangedCallback, userData: ?*c_void) callconv(.C) void {
    const lock = connection.mutex.acquire();
    defer lock.release();
    connection.on_property_changed = .{ .function = callback, .user_data = userData };
}

export fn dunstblick_GetUserData(connection: *app.Connection) callconv(.C) ?*c_void {
    return connection.user_data_pointer;
}

export fn dunstblick_SetUserData(connection: *app.Connection, userData: ?*c_void) callconv(.C) void {
    connection.user_data_pointer = userData;
}

export fn dunstblick_BeginChangeObject(con: *app.Connection, id: protocol.ObjectID) callconv(.C) ?*app.Object {
    return con.beginChangeObject(id) catch null;
}

export fn dunstblick_RemoveObject(con: *app.Connection, oid: protocol.ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.removeObject(oid));
}

export fn dunstblick_SetView(con: *app.Connection, id: protocol.ResourceID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setView(id));
}

export fn dunstblick_SetRoot(con: *app.Connection, id: protocol.ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setRoot(id));
}

export fn dunstblick_SetProperty(con: *app.Connection, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const app.Value) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setProperty(oid, name, value.*));
}

export fn dunstblick_Clear(con: *app.Connection, oid: protocol.ObjectID, name: protocol.PropertyName) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.clear(oid, name));
}

export fn dunstblick_InsertRange(con: *app.Connection, oid: protocol.ObjectID, name: protocol.PropertyName, index: u32, count: u32, values: [*]const protocol.ObjectID) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.insertRange(oid, name, index, values[0..count]));
}

export fn dunstblick_RemoveRange(con: *app.Connection, oid: protocol.ObjectID, name: protocol.PropertyName, index: u32, count: u32) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.removeRange(oid, name, index, count));
}

export fn dunstblick_MoveRange(con: *app.Connection, oid: protocol.ObjectID, name: protocol.PropertyName, indexFrom: u32, indexTo: u32, count: u32) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.moveRange(oid, name, indexFrom, indexTo, count));
}

// /*******************************************************************************
//  * Object Implementation *
//  *******************************************************************************/

export fn dunstblick_SetObjectProperty(obj: *app.Object, name: protocol.PropertyName, value: *const app.Value) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(obj.setProperty(name, value.*));
}

export fn dunstblick_CommitObject(obj: *app.Object) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(obj.commit());
}

export fn dunstblick_CancelObject(obj: *app.Object) callconv(.C) void {
    obj.cancel();
}

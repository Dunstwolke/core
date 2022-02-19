const std = @import("std");

const c = @cImport({
    @cDefine("DUNSTBLICK_NO_GLOBAL_NAMESPACE", "");
    @cInclude("dunstblick.h");
});

const protocol = @import("dunstblick-protocol");

const app = @import("dunstblick-app");

const DUNSTBLICK_MAX_APP_NAME_LENGTH = 64;

const NativeErrorCode = enum(c_int) {
    got_event = 1,

    /// The operation was successful.
    none = 0,

    /// An invalid argument was passed to the function.
    invalid_arg = -1,

    /// A network error happened.
    network = -2,

    /// An invalid type was passed to a function.
    invalid_type = -3,

    /// An argument was not in the allowed range.
    argument_out_of_range = -4,

    /// An allocation failed.
    out_of_memory = -5,

    /// A requested resource was not found.
    resource_not_found = -6,

    /// The dunstblick protocol was violated by the other host.
    protocol_violation = -7,
};

// Configure std.log
pub const log_level: std.log.Level = .err;

fn convertToSimilar(comptime Dst: type, src: anytype) Dst {
    const Src = @TypeOf(src);
    var dst = std.mem.zeroes(Dst);

    if (std.meta.fields(Src).len != std.meta.fields(Dst).len)
        @compileError("Field count must match!");

    inline for (std.meta.fields(Src)) |fld| {
        @field(dst, fld.name) = @field(src, fld.name);
    }

    return dst;
}

fn convertValueToZig(value: c.dunstblick_Value) app.Value {
    const data = value.value;
    return switch (value.type) {
        c.DUNSTBLICK_TYPE_INTEGER => app.Value{ .integer = data.integer },
        c.DUNSTBLICK_TYPE_NUMBER => app.Value{ .number = data.number },
        c.DUNSTBLICK_TYPE_STRING => app.Value{ .string = app.String.readOnly(std.mem.sliceTo(data.string, 0)) },
        c.DUNSTBLICK_TYPE_ENUMERATION => app.Value{ .enumeration = data.enumeration },
        c.DUNSTBLICK_TYPE_MARGINS => app.Value{ .margins = convertToSimilar(app.Margins, data.margins) },
        c.DUNSTBLICK_TYPE_COLOR => app.Value{ .color = convertToSimilar(app.Color, data.color) },
        c.DUNSTBLICK_TYPE_SIZE => app.Value{ .size = convertToSimilar(app.Size, data.size) },
        c.DUNSTBLICK_TYPE_POINT => app.Value{ .point = convertToSimilar(app.Point, data.point) },
        c.DUNSTBLICK_TYPE_RESOURCE => app.Value{ .resource = @intToEnum(app.ResourceID, data.resource) },
        c.DUNSTBLICK_TYPE_BOOLEAN => app.Value{ .boolean = data.boolean },
        c.DUNSTBLICK_TYPE_OBJECT => app.Value{ .object = @intToEnum(app.ObjectID, data.object) },
        c.DUNSTBLICK_TYPE_OBJECTLIST => @panic("OBJECTLIST not implemented yet!"), //  app.Value{},
        c.DUNSTBLICK_TYPE_EVENT => app.Value{ .event = @intToEnum(app.EventID, data.event) },
        c.DUNSTBLICK_TYPE_WIDGET_NAME => app.Value{ .widget = @intToEnum(app.WidgetName, data.widget_name) },

        else => std.debug.panicExtra(null, "Illegal value type {} passed", .{value.type}),
    };
}

fn convertValueToC(value: app.Value) c.dunstblick_Value {
    _ = value;
    @panic("not implemented yet");
}

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

fn pumpEvents(provider: *app.Application, dst_event: *c.dunstblick_Event, timeout: ?u64) NativeErrorCode {
    provider.mutex.lock();
    defer provider.mutex.unlock();

    if (provider.pollEvent(timeout) catch |err| return mapDunstblickError(err)) |src_event| {
        dst_event.* = switch (src_event.*) {
            .connected => |data| c.dunstblick_Event{
                .connected = .{
                    .type = c.DUNSTBLICK_EVENT_CONNECTED,

                    .connection = @ptrCast(*c.dunstblick_Connection, data.connection),
                    .screen_size = convertToSimilar(c.dunstblick_Size, data.screenSize),
                    .capabilities = blk: {
                        var caps: u32 = 0;

                        var mut_cap = data.capabilities;
                        var it = mut_cap.iterator();
                        while (it.next()) |item| {
                            caps |= @as(u32, 1) << @enumToInt(item);
                        }

                        break :blk caps;
                    },
                },
            },
            .disconnected => |data| c.dunstblick_Event{
                .disconnected = .{
                    .type = c.DUNSTBLICK_EVENT_DISCONNECTED,

                    .connection = @ptrCast(*c.dunstblick_Connection, data.connection),
                    .reason = @enumToInt(data.reason),
                },
            },
            .widget_event => |data| c.dunstblick_Event{
                .widget_event = .{
                    .type = c.DUNSTBLICK_EVENT_WIDGET,

                    .connection = @ptrCast(*c.dunstblick_Connection, data.connection),
                    .event = @enumToInt(data.event),
                    .caller = @enumToInt(data.caller),
                },
            },
            .property_changed => |data| c.dunstblick_Event{
                .property_changed = .{
                    .type = c.DUNSTBLICK_EVENT_PROPERTY_CHANGED,

                    .connection = @ptrCast(*c.dunstblick_Connection, data.connection),
                    .object = @enumToInt(data.object),
                    .property = @enumToInt(data.property),
                    .value = convertValueToC(data.value),
                },
            },
        };
        return .got_event;
    } else {
        dst_event.* = .{
            .type = c.DUNSTBLICK_EVENT_NONE,
        };
        return .none;
    }
}

export fn dunstblick_PumpEvents(provider: *app.Application, event: *c.dunstblick_Event) callconv(.C) NativeErrorCode {
    return pumpEvents(provider, event, 10 * std.time.ms_per_s);
}

export fn dunstblick_WaitEvent(provider: *app.Application, event: *c.dunstblick_Event) callconv(.C) NativeErrorCode {
    return pumpEvents(provider, event, null);
}

export fn dunstblick_AddResource(provider: *app.Application, resourceID: protocol.ResourceID, kind: protocol.ResourceKind, data: *const anyopaque, length: usize) callconv(.C) NativeErrorCode {
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
    _ = connection;
    return "unknown"; // TODO: Reintrocude client names?
}

export fn dunstblick_GetDisplaySize(connection: *app.Connection) callconv(.C) app.Size {
    connection.mutex.lock();
    defer connection.mutex.unlock();
    return connection.screen_resolution;
}

export fn dunstblick_GetUserData(connection: *app.Connection) callconv(.C) ?*anyopaque {
    return connection.user_data_pointer;
}

export fn dunstblick_SetUserData(connection: *app.Connection, userData: ?*anyopaque) callconv(.C) void {
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

export fn dunstblick_SetProperty(con: *app.Connection, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const c.dunstblick_Value) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(con.setProperty(oid, name, convertValueToZig(value.*)));
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

export fn dunstblick_SetObjectProperty(obj: *app.Object, name: protocol.PropertyName, value: *const c.dunstblick_Value) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(obj.setProperty(name, convertValueToZig(value.*)));
}

export fn dunstblick_CommitObject(obj: *app.Object) callconv(.C) NativeErrorCode {
    return mapDunstblickErrorVoid(obj.commit());
}

export fn dunstblick_CancelObject(obj: *app.Object) callconv(.C) void {
    obj.cancel();
}

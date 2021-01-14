const protocol = @import("dunstblick-protocol");
const sdl = @import("sdl2");

const painting = @import("painting.zig");

usingnamespace @import("types.zig");

pub const ZigSession = opaque {};

pub const Object = opaque {};

pub extern fn session_pushEvent(current_session: *ZigSession, e: *const sdl.c.SDL_Event) void;

pub extern fn session_getCursor(session: *ZigSession) sdl.c.SDL_SystemCursor;

pub extern fn session_render(session: *ZigSession, screen_rect: Rectangle, painter: *painting.PainterAPI) void;

// ZigSession Class

/// Callback interface for the C++ code
pub const ZigSessionApi = extern struct {
    const Self = @This();

    trigger_event: fn (api: *Self, event: protocol.EventID, widget: protocol.WidgetName) callconv(.C) void,

    trigger_propertyChanged: fn (api: *Self, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const protocol.Value) callconv(.C) void,
};

pub extern fn zsession_create(api: *ZigSessionApi) ?*ZigSession;

pub extern fn zsession_destroy(session: *ZigSession) void;

pub extern fn zsession_uploadResource(session: *ZigSession, resource_id: protocol.ResourceID, kind: protocol.ResourceKind, data: [*]const u8, len: usize) void;

pub extern fn zsession_addOrUpdateObject(session: *ZigSession, obj: *Object) void;

pub extern fn zsession_removeObject(session: *ZigSession, obj: protocol.ObjectID) void;

pub extern fn zsession_setView(session: *ZigSession, id: protocol.ResourceID) void;

pub extern fn zsession_setRoot(session: *ZigSession, obj: protocol.ObjectID) void;

pub extern fn zsession_setProperty(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName, value: *const protocol.Value) void;

pub extern fn zsession_clear(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName) void;

pub extern fn zsession_insertRange(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName, index: usize, count: usize, values: [*]const protocol.ObjectID) void;

pub extern fn zsession_removeRange(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName, index: usize, count: usize) void;

pub extern fn zsession_moveRange(session: *ZigSession, obj: protocol.ObjectID, prop: protocol.PropertyName, indexFrom: usize, indexTo: usize, count: usize) void;

pub extern fn object_create(id: protocol.ObjectID) ?*Object;

pub extern fn object_addProperty(object: *Object, prop: protocol.PropertyName, value: *const protocol.Value) bool;

pub extern fn object_destroy(object: *Object) void;

const std = @import("std");
const cpp = @import("cpp.zig");
const protocol = @import("dunstblick-protocol");
const log = std.log.scoped(.app);

const app_discovery = @import("app-discovery.zig");

const Session = @import("session.zig").Session;
const WindowCollection = @import("window-collection.zig").WindowCollection;
const NetworkSession = @import("network-session.zig").NetworkSession;

pub const DiscoverySession = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    api: cpp.ZigSessionApi,
    driver: Session,

    windows: *WindowCollection,
    alive: bool = true,

    const resource_names = struct {
        const discovery_menu = @intToEnum(protocol.ResourceID, 1);
        const discovery_list_item = @intToEnum(protocol.ResourceID, 2);
    };

    const object_names = struct {
        const root = @intToEnum(protocol.ObjectID, 1);
    };

    const properties = struct {
        const local_discovery_list = @intToEnum(protocol.PropertyName, 1);
        const local_app_name = @intToEnum(protocol.PropertyName, 2);
        const local_app_ip = @intToEnum(protocol.PropertyName, 3);
        const local_app_port = @intToEnum(protocol.PropertyName, 4);
        const local_app_id = @intToEnum(protocol.PropertyName, 5);
    };

    const events = struct {
        const local_exit_client_event = @intToEnum(protocol.EventID, 1);
        const local_open_session_event = @intToEnum(protocol.EventID, 2);
        const local_close_session_event = @intToEnum(protocol.EventID, 3);
    };

    /// Must be a non-moveable object → heap allocate
    pub fn create(allocator: *std.mem.Allocator, windows: *WindowCollection) !*Self {
        var session = try allocator.create(Self);
        errdefer allocator.destroy(session);

        const Binding = struct {
            fn destroy(ctx: *Session) void {
                const self = @fieldParentPtr(Self, "driver", ctx);
                self.destroy();
            }
            fn update(ctx: *Session) error{OutOfMemory}!bool {
                const self = @fieldParentPtr(Self, "driver", ctx);
                return try self.update();
            }
        };

        session.* = Self{
            .allocator = allocator,
            .api = cpp.ZigSessionApi{
                .trigger_event = zsession_triggerEvent,
                .trigger_propertyChanged = zsession_triggerPropertyChanged,
            },
            .driver = Session{
                .cpp_session = undefined,
                .update = Binding.update,
                .destroy = Binding.destroy,
            },
            .windows = windows,
        };

        session.driver.cpp_session = cpp.zsession_create(&session.api) orelse return error.OutOfMemory;

        const root_layout: []const u8 = @embedFile("./layouts/discovery-menu.cui");
        cpp.zsession_uploadResource(
            session.driver.cpp_session,
            resource_names.discovery_menu,
            .layout,
            root_layout.ptr,
            root_layout.len,
        );

        const item_layout: []const u8 = @embedFile("./layouts/discovery-list-item.cui");
        cpp.zsession_uploadResource(
            session.driver.cpp_session,
            resource_names.discovery_list_item,
            .layout,
            item_layout.ptr,
            item_layout.len,
        );

        cpp.zsession_setView(
            session.driver.cpp_session,
            resource_names.discovery_menu,
        );

        {
            const obj = cpp.object_create(object_names.root) orelse return error.OutOfMemory;
            errdefer cpp.object_destroy(obj);

            const success = cpp.object_addProperty(obj, properties.local_discovery_list, &protocol.Value{
                .type = .objectlist,
                .value = undefined,
            });
            std.debug.assert(success == true);

            cpp.zsession_addOrUpdateObject(session.driver.cpp_session, obj);
        }

        cpp.zsession_setRoot(
            session.driver.cpp_session,
            object_names.root,
        );

        return session;
    }

    pub fn destroy(self: *Self) void {
        cpp.zsession_destroy(self.driver.cpp_session);
        self.allocator.destroy(self);
    }

    pub fn update(self: *Self) !bool {
        var list = app_discovery.getDiscovereyApplications();
        defer list.release();

        var app_ids = std.ArrayList(protocol.ObjectID).init(self.allocator);
        defer app_ids.deinit();

        for (list.applications) |app, i| {
            const id = @intToEnum(protocol.ObjectID, @intCast(u32, 1000 + i));

            {
                const obj = cpp.object_create(id) orelse return error.OutOfMemory;
                errdefer cpp.object_destroy(obj);

                if (cpp.object_addProperty(obj, properties.local_app_name, &protocol.Value{
                    .type = .string,
                    .value = .{
                        .string = app.name.ptr,
                    },
                }) == false) {
                    unreachable;
                }

                if (cpp.object_addProperty(obj, properties.local_app_port, &protocol.Value{
                    .type = .integer,
                    .value = .{
                        .integer = app.tcp_port,
                    },
                }) == false) {
                    unreachable;
                }

                var addr_buf: [256]u8 = undefined;
                var ip_str = std.fmt.bufPrint(&addr_buf, "{}\x00", .{app.address}) catch unreachable;

                if (cpp.object_addProperty(obj, properties.local_app_ip, &protocol.Value{
                    .type = .string,
                    .value = .{
                        // space should be sufficient for both IPv4 and IPv6
                        .string = @ptrCast([*:0]const u8, &addr_buf),
                    },
                }) == false) {
                    unreachable;
                }

                if (cpp.object_addProperty(obj, properties.local_app_id, &protocol.Value{
                    .type = .name,
                    .value = .{
                        .name = @intToEnum(protocol.WidgetName, @intCast(u32, i + 1)),
                    },
                }) == false) {
                    unreachable;
                }

                cpp.zsession_addOrUpdateObject(self.driver.cpp_session, obj);
            }

            try app_ids.append(id);
        }

        cpp.zsession_clear(self.driver.cpp_session, object_names.root, properties.local_discovery_list);
        cpp.zsession_insertRange(self.driver.cpp_session, object_names.root, properties.local_discovery_list, 0, app_ids.items.len, app_ids.items.ptr);
        return self.alive;
    }

    fn zsession_triggerEvent(api: *cpp.ZigSessionApi, event: protocol.EventID, widget: protocol.WidgetName) callconv(.C) void {
        const self = @fieldParentPtr(Self, "api", api);
        switch (event) {
            events.local_exit_client_event => self.alive = false,
            events.local_open_session_event => {
                if (widget == .none) {
                    log.warn("got open-session-event for unnamed widget.", .{});
                    return;
                }

                var list = app_discovery.getDiscovereyApplications();
                defer list.release();

                const index = @enumToInt(widget) - 1;
                if (index >= list.applications.len) {
                    log.warn("got open-session-event for invalid app: {}; {}", .{
                        list.applications.len,
                        index,
                    });
                    return;
                }

                const app = &list.applications[index];

                const session = NetworkSession.create(self.allocator, app.*) catch |err| {
                    log.err("failed to create new network session for : {}; {}", .{
                        list.applications.len,
                        index,
                    });
                    return;
                };

                const window = self.windows.addWindow(app.name, 640, 480, &session.driver) catch |err| {
                    session.destroy();

                    log.err("failed to create window for network session: {}", .{
                        err,
                    });
                    return;
                };

                // Make this async for the future
                session.connect() catch |err| {
                    self.windows.close(window);

                    log.err("failed to connect to application: {}", .{
                        err,
                    });
                    return;
                };
            },

            events.local_close_session_event => {
                log.info("close session for {}", .{@enumToInt(widget)});
            },

            else => log.info("zsession_triggerEvent: {} {}", .{ event, widget }),
        }
    }

    fn zsession_triggerPropertyChanged(api: *cpp.ZigSessionApi, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const protocol.Value) callconv(.C) void {
        std.debug.print("zsession_triggerPropertyChanged: {} {} {}\n", .{ oid, name, value });
    }
};

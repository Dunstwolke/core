const std = @import("std");
const cpp = @import("cpp.zig");
const protocol = @import("dunstblick-protocol");
const network = @import("network");
const log = std.log.scoped(.app);

const app_discovery = @import("app-discovery.zig");

const Session = @import("session.zig").Session;

pub const NetworkSession = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    api: cpp.ZigSessionApi,
    driver: Session,

    target_ip: network.Address,
    target_port: u16,

    connection: ?network.Socket,
    alive: bool = true,

    /// Must be a non-moveable object → heap allocate
    pub fn create(allocator: *std.mem.Allocator, application: app_discovery.Application) !*Self {
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
            .connection = null,
            .target_ip = application.address,
            .target_port = application.tcp_port,
        };

        session.driver.cpp_session = cpp.zsession_create(&session.api) orelse return error.OutOfMemory;

        return session;
    }

    pub fn connect(self: *Self) !void {
        std.debug.assert(self.connection == null);

        self.connection = try network.Socket.create(.ipv4, .tcp);

        const sock = &self.connection.?;
        errdefer sock.close();

        try sock.connect(network.EndPoint{
            .address = self.target_ip,
            .port = self.target_port,
        });

        var writer = sock.writer();
        var reader = sock.reader();

        try writer.writeAll(std.mem.asBytes(&protocol.tcp.ConnectHeader{
            .name = sliceToArray(u8, 32, "Test Client", 0),
            .password = sliceToArray(u8, 32, "", 0),
            .screen_size_x = 640, // TODO: Set to real values here
            .screen_size_y = 480,
            .capabilities = .{
                .mouse = true,
                .keyboard = true,
            },
        }));

        var connect_response: protocol.tcp.ConnectResponse = undefined;
        try reader.readNoEof(std.mem.asBytes(&connect_response));

        if (connect_response.success != 1)
            return error.AuthenticationFailure;

        var resources = std.AutoHashMap(protocol.ResourceID, protocol.tcp.ResourceDescriptor).init(self.allocator);
        defer resources.deinit();

        var i: usize = 0;
        while (i < connect_response.resource_count) : (i += 1) {
            var resource_descriptor: protocol.tcp.ResourceDescriptor = undefined;

            try reader.readNoEof(std.mem.asBytes(&resource_descriptor));

            try resources.put(resource_descriptor.id, resource_descriptor);

            log.debug(
                \\Resource[{}]:
                \\  id:   {}
                \\  type: {}
                \\  size: {}
                \\  hash: {}
                \\
            , .{
                i,
                resource_descriptor.id,
                resource_descriptor.type,
                resource_descriptor.size,
                std.fmt.fmtSliceHexUpper(&resource_descriptor.hash),
            });
        }

        try writer.writeAll(std.mem.asBytes(&protocol.tcp.ResourceRequestHeader{
            .request_count = @intCast(u32, resources.count()),
        }));

        var res_iter = resources.iterator();
        while (res_iter.next()) |item| {
            try writer.writeAll(std.mem.asBytes(&protocol.tcp.ResourceRequest{
                .id = item.key,
            }));
        }

        var byte_buffer = std.ArrayList(u8).init(self.allocator);
        defer byte_buffer.deinit();

        i = 0;
        while (i < resources.count()) : (i += 1) {
            var resource_header: protocol.tcp.ResourceHeader = undefined;
            try reader.readNoEof(std.mem.asBytes(&resource_header));

            log.info("Receiving resource {} ({} bytes)…", .{ resource_header.id, resource_header.size });

            try byte_buffer.resize(resource_header.size);

            try reader.readNoEof(byte_buffer.items);

            const resource_descriptor = resources.get(resource_header.id) orelse return error.InvalidResourceID;

            cpp.zsession_uploadResource(
                self.driver.cpp_session,
                resource_descriptor.id,
                resource_descriptor.type,
                byte_buffer.items.ptr,
                byte_buffer.items.len,
            );
        }
    }

    pub fn destroy(self: *Self) void {
        if (self.connection) |sock| {
            sock.close();
        }
        cpp.zsession_destroy(self.driver.cpp_session);
        self.allocator.destroy(self);
    }

    pub fn update(self: *Self) error{OutOfMemory}!bool {
        if (self.connection == null)
            return self.alive;
        const sock = &self.connection.?;

        var packet = std.ArrayList(u8).init(self.allocator);
        defer packet.deinit();

        var socket_set = network.SocketSet.init(self.allocator) catch return error.OutOfMemory;
        defer socket_set.deinit();

        try socket_set.add(sock.*, .{
            .read = true,
            .write = false,
        });

        while (true) {
            _ = network.waitForSocketEvent(&socket_set, 0) catch |err| {
                log.crit("Waiting for socket event failed with {}", .{err});
                return false;
            };

            if (!socket_set.isReadyRead(sock.*))
                break;

            var reader = sock.reader();

            const length = reader.readIntLittle(u32) catch {
                self.alive = false;
                return false;
            };

            try packet.resize(length);

            reader.readNoEof(packet.items) catch {
                self.alive = false;
                return false;
            };

            self.parseAndExecMsg(packet.items) catch {
                self.alive = false;
                return false;
            };
        }

        return self.alive;
    }

    fn parseAndExecMsg(self: *Self, packet: []const u8) !void {
        log.info("Received packet of {} bytes: {}", .{
            packet.len,
            std.fmt.fmtSliceHexUpper(packet),
        });

        var decoder = protocol.Decoder.init(packet);

        const message_type = @intToEnum(protocol.DisplayCommand, try decoder.readByte());

        switch (message_type) {
            .uploadResource => { // (rid, kind, data)
                const resource = @intToEnum(protocol.ResourceID, try decoder.readVarUInt());
                const kind = @intToEnum(protocol.ResourceKind, try decoder.readByte());

                const data = try decoder.readToEnd();

                cpp.zsession_uploadResource(
                    self.driver.cpp_session,
                    resource,
                    kind,
                    data.ptr,
                    data.len,
                );
            },

            .addOrUpdateObject => { // (obj)
                const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());

                var obj = cpp.object_create(oid) orelse return error.OutOfMemory;
                errdefer cpp.object_destroy(obj);

                while (true) {
                    const value_type = @intToEnum(protocol.Type, try decoder.readByte());
                    if (value_type == .none) {
                        break;
                    }

                    const prop = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());

                    log.debug("read value of type {}", .{value_type});

                    const value = try decoder.readValue(value_type, self.allocator);
                    defer decoder.deinitValue(value, self.allocator);

                    const success = cpp.object_addProperty(
                        obj,
                        prop,
                        &value,
                    );
                    if (!success) {
                        return error.OutOfMemory;
                    }
                }

                cpp.zsession_addOrUpdateObject(self.driver.cpp_session, obj);
            },

            .removeObject => { // (oid)
                const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
                cpp.zsession_removeObject(self.driver.cpp_session, oid);
            },

            .setView => { // (rid)
                const rid = @intToEnum(protocol.ResourceID, try decoder.readVarUInt());
                cpp.zsession_setView(self.driver.cpp_session, rid);
            },

            .setRoot => { // (oid)
                const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
                cpp.zsession_setRoot(self.driver.cpp_session, oid);
            },

            .setProperty => { // (oid, name, value)
                const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());

                const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());

                const value_type = @intToEnum(protocol.Type, try decoder.readByte());
                const value = try decoder.readValue(value_type, self.allocator);
                defer decoder.deinitValue(value, self.allocator);

                cpp.zsession_setProperty(
                    self.driver.cpp_session,
                    oid,
                    propName,
                    &value,
                );
            },

            .clear => { // (oid, name)
                const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
                const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());

                cpp.zsession_clear(
                    self.driver.cpp_session,
                    oid,
                    propName,
                );
            },

            .insertRange => { // (oid, name, index, count, oids …) // manipulate lists
                const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
                const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());
                const index = try decoder.readVarUInt();
                const count = try decoder.readVarUInt();

                var refs = std.ArrayList(protocol.ObjectID).init(self.allocator);
                defer refs.deinit();

                try refs.resize(count);

                for (refs.items) |*item| {
                    item.* = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
                }

                cpp.zsession_insertRange(
                    self.driver.cpp_session,
                    oid,
                    propName,
                    index,
                    count,
                    refs.items.ptr,
                );
            },

            .removeRange => { // (oid, name, index, count) // manipulate lists
                const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
                const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());
                const index = try decoder.readVarUInt();
                const count = try decoder.readVarUInt();
                cpp.zsession_removeRange(
                    self.driver.cpp_session,
                    oid,
                    propName,
                    index,
                    count,
                );
            },

            .moveRange => { // (oid, name, indexFrom, indexTo, count) // manipulate lists
                const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
                const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());
                const indexFrom = try decoder.readVarUInt();
                const indexTo = try decoder.readVarUInt();
                const count = try decoder.readVarUInt();
                cpp.zsession_moveRange(
                    self.driver.cpp_session,
                    oid,
                    propName,
                    indexFrom,
                    indexTo,
                    count,
                );
            },

            else => {
                log.warn("received message of unknown type: {}", .{
                    message_type,
                });
            },
        }
    }

    fn zsession_triggerEvent(api: *cpp.ZigSessionApi, event: protocol.EventID, widget: protocol.WidgetName) callconv(.C) void {
        const self = @fieldParentPtr(Self, "api", api);
        log.debug("zsession_triggerEvent: {} {}", .{ event, widget });

        // ignore empty callbacks
        if (event != .invalid) {
            var backing_buf: [128]u8 = undefined;
            var stream = std.io.fixedBufferStream(&backing_buf);

            // we have enough storage :)
            var buffer = protocol.beginApplicationCommandEncoding(stream.writer(), .eventCallback) catch unreachable;
            buffer.writeID(@enumToInt(event)) catch unreachable;
            buffer.writeID(@enumToInt(widget)) catch unreachable;

            self.sendMessage(stream.getWritten()) catch |err| {
                log.err("Failed to send eventCallback message: {}", .{err});
                return;
            };
        }
    }

    fn zsession_triggerPropertyChanged(api: *cpp.ZigSessionApi, oid: protocol.ObjectID, name: protocol.PropertyName, value: *const protocol.Value) callconv(.C) void {
        const self = @fieldParentPtr(Self, "api", api);
        log.debug("zsession_triggerPropertyChanged: {} {} {}", .{ oid, name, value });

        if (oid == .invalid)
            return;
        if (name == .invalid)
            return;
        if (value.type == .none)
            return;

        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = protocol.beginApplicationCommandEncoding(stream.writer(), .propertyChanged) catch unreachable;

        buffer.writeID(@enumToInt(oid)) catch |err| {
            log.err("Failed to send propertyChanged message: {}", .{err});
            return;
        };
        buffer.writeID(@enumToInt(name)) catch |err| {
            log.err("Failed to send propertyChanged message: {}", .{err});
            return;
        };
        buffer.writeValue(value.*, true) catch |err| {
            log.err("Failed to send propertyChanged message: {}", .{err});
            return;
        };

        self.sendMessage(stream.getWritten()) catch |err| {
            log.err("Failed to send propertyChanged message: {}", .{err});
            return;
        };
    }

    fn sendMessage(self: *Self, packet: []const u8) !void {
        // std::lock_guard _{send_lock};
        if (self.connection) |sock| {
            std.debug.assert(packet.len <= std.math.maxInt(u32));

            const len = @intCast(u32, packet.len);

            var writer = sock.writer();
            try writer.writeIntLittle(u32, len);
            try writer.writeAll(packet);
        }
    }
};

fn sliceToArray(comptime T: type, comptime L: usize, data: []const T, fill: T) [L]T {
    if (data.len >= L) {
        return data[0..L].*;
    } else {
        var result: [L]T = undefined;
        std.mem.copy(T, result[0..], data);
        std.mem.set(T, result[data.len..], fill);
        return result;
    }
}

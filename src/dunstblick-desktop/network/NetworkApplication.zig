const std = @import("std");
const zero_graphics = @import("zero-graphics");
const network = @import("network");
const protocol = @import("dunstblick-protocol");
const logger = std.log.scoped(.network_application);
const builtin = @import("builtin");

const AppDiscovery = @import("AppDiscovery.zig");
const ApplicationInstance = @import("../gui/ApplicationInstance.zig");
const ApplicationDescription = @import("../gui/ApplicationDescription.zig");

const DunstblickUI = @import("../dunst-ui/DunstblickUI.zig");

const Size = zero_graphics.Size;

const State = enum {
    unconnected,
    socket_connecting,
    protocol_connecting,
    connected,
    faulted,
};

const Resource = struct {
    kind: protocol.ResourceKind,
    hash: [8]u8,
};

const Self = @This();

flagged_for_deletion: bool = false,
instance: ApplicationInstance,
allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

socket: ?network.Socket,

remote_end_point: network.EndPoint,

client: protocol.tcp.ClientStateMachine(network.Socket.Writer),

state: State = .unconnected,

screen_size: Size,

resources: std.AutoArrayHashMap(protocol.ResourceID, Resource),

discovery: *AppDiscovery,

user_interface: DunstblickUI,

const support_non_block = (builtin.os.tag == .linux and builtin.abi != .android);

pub fn init(self: *Self, allocator: std.mem.Allocator, app_desc: *const AppDiscovery.Application) !void {
    self.* = Self{
        .instance = ApplicationInstance{
            .description = app_desc.description,
            .vtable = ApplicationInstance.Interface.get(Interface),
        },
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .socket = null,
        .client = undefined,
        .remote_end_point = network.EndPoint{
            .address = app_desc.address,
            .port = app_desc.tcp_port,
        },
        .screen_size = Size.empty,
        .resources = std.AutoArrayHashMap(protocol.ResourceID, Resource).init(allocator),
        .discovery = app_desc.discovery,
        .user_interface = DunstblickUI.init(allocator, DunstblickUI.FeedbackInterface{
            .erased_self = @ptrCast(*DunstblickUI.FeedbackInterface.ErasedSelf, self),
            .trigger_event = triggerEvent,
            .trigger_property_changed = triggerPropertyChanged,
        }),
    };

    self.socket = try network.Socket.create(std.meta.activeTag(app_desc.address), .tcp);
    errdefer self.socket.?.close();

    self.client = protocol.tcp.ClientStateMachine(network.Socket.Writer).init(allocator, self.socket.?.writer());
    errdefer self.client.deinit();

    self.instance.description.display_name = try self.arena.allocator().dupeZ(u8, self.instance.description.display_name);
    if (self.instance.description.icon) |*icon| {
        icon.* = try self.arena.allocator().dupe(u8, icon.*);
    }

    self.instance.status = .{ .starting = "Connecting..." };

    if (support_non_block) {
        var flags = try std.os.fcntl(self.socket.?.internal, std.os.F.GETFL, 0);
        flags |= @as(usize, std.os.O.NONBLOCK);
        _ = try std.os.fcntl(self.socket.?.internal, std.os.F.SETFL, flags);
    }

    try self.discovery.socket_set.add(self.socket.?, .{ .read = true, .write = support_non_block });
    errdefer self.discovery.socket_set.remove(self.socket.?);

    try self.tryConnect();
}

pub fn deinit(self: *Self) void {
    if (self.socket) |*sock| {
        self.client.deinit();
        sock.close();
    }
    self.user_interface.deinit();
    self.arena.deinit();
    self.* = undefined;
    self.flagged_for_deletion = true;
}

pub fn isFaulted(self: Self) bool {
    return self.state == .faulted;
}

fn tryConnect(self: *Self) !void {
    std.debug.assert(self.socket != null);

    if (self.socket.?.connect(self.remote_end_point)) {
        // remove blocking from socket
        if (support_non_block) {
            var flags = try std.os.fcntl(self.socket.?.internal, std.os.F.GETFL, 0);
            flags &= ~@as(usize, std.os.O.NONBLOCK);
            _ = try std.os.fcntl(self.socket.?.internal, std.os.F.SETFL, flags);
        }

        // start handshaking
        try self.client.initiateHandshake(null, null);

        self.instance.status = .{ .starting = "Loading resources..." };
        self.state = .protocol_connecting;
    } else |err| {
        switch (err) {
            error.ConnectionRefused => {
                self.state = .faulted;
                self.instance.status = .{ .exited = "Connection refused" };
            },
            error.WouldBlock => {
                self.state = .socket_connecting;
            },
            else => |e| return e,
        }
    }
    // logger.info("tryConnect() => {}", .{self.state});
}

pub fn notifyWritable(self: *Self) !void {
    // logger.info("socket write {}", .{self.state});
    switch (self.state) {
        .unconnected => return error.InvalidState,

        .socket_connecting => {
            try self.tryConnect();
            if (self.state != .socket_connecting) {
                if (self.socket) |sock| {
                    self.discovery.socket_set.remove(sock);
                    try self.discovery.socket_set.add(sock, .{ .read = true, .write = false });
                }
            }
        },

        .protocol_connecting, .connected, .faulted => {},
    }
}

pub fn notifyReadable(self: *Self) !void {
    // logger.info("socket read {}", .{self.state});
    switch (self.state) {
        .unconnected, .socket_connecting => return error.InvalidState,

        .protocol_connecting, .connected => {
            var backing_buffer: [8192]u8 = undefined;

            const len = try self.socket.?.receive(&backing_buffer);

            if (len == 0) {
                self.disconnect(null);
                self.instance.status = .{ .exited = "Lost connection to application." };
                return;
            }

            const buffer = backing_buffer[0..len];

            var offset: usize = 0;
            while (offset < buffer.len) {
                const push_info = try self.client.pushData(buffer[offset..]);
                offset += push_info.consumed;
                if (push_info.event) |event| {
                    // logger.debug("received event: {s}", .{@tagName(std.meta.activeTag(event))});
                    switch (event) {
                        .acknowledge_handshake => |data| { //  AcknowledgeHandshake{ .requires_username = false, .requires_password = false, .rejects_username = false, .rejects_password = false } }
                            if (!data.ok()) {
                                self.disconnect(null);
                            }
                            // TODO: Send auth info if required
                        },
                        .authenticate_result => |data| { //  AuthenticateResult{ .result = Result.success } }
                            if (data.result != .success) {
                                self.instance.status = .{ .exited = switch (data.result) {
                                    .success => unreachable,
                                    .invalid_credentials => "Invalid credentials",
                                } };
                                self.disconnect(null);
                            } else {
                                try self.client.sendConnectHeader(
                                    self.screen_size.width,
                                    self.screen_size.height,
                                    std.EnumSet(protocol.ClientCapabilities).init(.{
                                        .mouse = true,
                                        .keyboard = true,
                                        .touch = true,
                                        .highdpi = false,
                                        .tiltable = false,
                                        .resizable = true,
                                        .req_accessibility = false,
                                    }),
                                );
                            }
                        },
                        .connect_response => |info| {
                            // TODO: Request available resources
                            logger.info("server provides {} resources", .{info.resource_count});
                        },
                        .connect_response_item => |info| {
                            const gop = try self.resources.getOrPut(info.descriptor.id);
                            if (gop.found_existing) {
                                self.disconnect(null);
                                self.instance.status = .{ .exited = "protocol violation: dup res" };
                                return;
                            }
                            gop.value_ptr.* = .{
                                .kind = info.descriptor.type,
                                .hash = info.descriptor.hash,
                            };

                            if (info.is_last) {
                                // just request all resources

                                var temp_list = std.ArrayList(protocol.ResourceID).init(self.allocator);
                                defer temp_list.deinit();

                                try temp_list.ensureTotalCapacity(self.resources.count());
                                var it = self.resources.iterator();
                                while (it.next()) |res| {
                                    temp_list.appendAssumeCapacity(res.key_ptr.*);
                                }

                                try self.client.sendResourceRequest(temp_list.items);
                            }
                        },
                        .resource_header => |info| {
                            if (self.resources.getEntry(info.resource_id)) |entry| {
                                const received_hash = protocol.computeResourceHash(info.data);
                                if (!std.mem.eql(u8, &received_hash, &entry.value_ptr.hash)) {
                                    self.disconnect(null);
                                    self.instance.status = .{ .exited = "protocol violation: invalid hash" };
                                    return;
                                }

                                try self.user_interface.addOrReplaceResource(
                                    info.resource_id,
                                    entry.value_ptr.kind,
                                    info.data,
                                );
                            } else {
                                self.disconnect(null);
                                self.instance.status = .{ .exited = "protocol violation: invalid res" };
                                return;
                            }
                        },
                        .message => |packet| {
                            self.decodeAndExecuteMessage(packet) catch |err| {
                                logger.err("received invalid message: {s}", .{@errorName(err)});
                                self.disconnect(null);
                                self.instance.status = .{ .exited = "protocol violation: received invalid message" };
                                return;
                            };
                        },
                    }

                    if (self.client.isConnectionEstablished()) {
                        // we're done with doing handshake stuff,
                        // we're ready to go :)
                        self.instance.status = .running;
                        self.state = .connected;
                    }
                }
            }
        },
        .faulted => {
            if (self.socket) |sock| {
                var backing_buffer: [8192]u8 = undefined;

                const len = try sock.receive(&backing_buffer);
                if (len == 0) {
                    self.disconnect(null);
                    self.instance.status = .{ .exited = "Lost connection to application." };
                } else {
                    logger.info("received {} byte in faulted state: {}", .{
                        len,
                        std.fmt.fmtSliceHexLower(backing_buffer[0..len]),
                    });
                }
            } else {
                return error.InvalidState;
            }
        },
    }
}

fn decodeAndExecuteMessage(self: *Self, packet: []const u8) !void {
    // logger.info("Received packet of {} bytes: {}", .{
    //     packet.len,
    //     std.fmt.fmtSliceHexUpper(packet),
    // });

    var decoder = protocol.Decoder.init(packet);

    const message_type = @intToEnum(protocol.DisplayCommand, try decoder.readByte());

    switch (message_type) {
        .uploadResource => { // (rid, kind, data)
            const resource = @intToEnum(protocol.ResourceID, try decoder.readVarUInt());
            const kind = @intToEnum(protocol.ResourceKind, try decoder.readByte());

            const data = try decoder.readToEnd();

            try self.user_interface.addOrReplaceResource(resource, kind, data);
        },

        .addOrUpdateObject => { // (obj)
            const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());

            var obj = DunstblickUI.Object.init(self.allocator, oid);
            errdefer obj.deinit();

            while (true) {
                const value_tag = try decoder.readByte();
                if (value_tag == 0)
                    break;
                const value_type = @intToEnum(protocol.Type, value_tag);

                const prop = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());

                var value = try DunstblickUI.Value.deserialize(self.allocator, value_type, &decoder);
                errdefer value.deinit();

                try obj.addProperty(prop, value);
            }

            try self.user_interface.addOrUpdateObject(obj);
        },

        .removeObject => { // (oid)
            const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
            self.user_interface.removeObject(oid);
        },

        .setView => { // (rid)
            const rid = @intToEnum(protocol.ResourceID, try decoder.readVarUInt());
            try self.user_interface.setView(rid);
        },

        .setRoot => { // (oid)
            const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
            try self.user_interface.setRoot(oid);
        },

        .setProperty => { // (oid, name, value)
            const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());

            const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());

            const value_type = @intToEnum(protocol.Type, try decoder.readByte());

            var value = try DunstblickUI.Value.deserialize(self.allocator, value_type, &decoder);
            errdefer value.deinit();

            if (self.user_interface.getObject(oid)) |object| {
                try object.setProperty(propName, value);
            } else {
                logger.err("object {} does not exist!", .{@enumToInt(oid)});
            }
        },

        .clear => { // (oid, name)
            const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
            const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());

            if (self.user_interface.getObject(oid)) |object| {
                try object.clear(propName);
            } else {
                logger.err("object {} does not exist!", .{@enumToInt(oid)});
            }
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

            if (self.user_interface.getObject(oid)) |object| {
                try object.insertRange(propName, index, refs.items);
            } else {
                logger.err("object {} does not exist!", .{@enumToInt(oid)});
            }
        },

        .removeRange => { // (oid, name, index, count) // manipulate lists
            const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
            const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());
            const index = try decoder.readVarUInt();
            const count = try decoder.readVarUInt();

            if (self.user_interface.getObject(oid)) |object| {
                try object.removeRange(propName, index, count);
            } else {
                logger.err("object {} does not exist!", .{@enumToInt(oid)});
            }
        },

        .moveRange => { // (oid, name, indexFrom, indexTo, count) // manipulate lists
            const oid = @intToEnum(protocol.ObjectID, try decoder.readVarUInt());
            const propName = @intToEnum(protocol.PropertyName, try decoder.readVarUInt());
            const indexFrom = try decoder.readVarUInt();
            const indexTo = try decoder.readVarUInt();
            const count = try decoder.readVarUInt();

            if (self.user_interface.getObject(oid)) |object| {
                try object.moveRange(propName, indexFrom, indexTo, count);
            } else {
                logger.err("object {} does not exist!", .{@enumToInt(oid)});
            }
        },

        .disconnect => {
            const reason = try decoder.readString(self.arena.allocator());
            self.disconnect(null);

            self.instance.status = .{ .exited = reason };
        },

        else => {
            logger.warn("received message of unknown type: {}", .{
                message_type,
            });
        },
    }
}

fn mapEncodeError(err: std.io.FixedBufferStream([]u8).WriteError) DunstblickUI.FeedbackInterface.Error {
    return switch (err) {
        error.NoSpaceLeft => error.OutOfMemory,
    };
}

fn mapSendError(err: protocol.tcp.ClientStateMachine(network.Socket.Writer).SendError) DunstblickUI.FeedbackInterface.Error {
    return switch (err) {
        // error.OutOfMemory => error.OutOfMemory,
        else => return error.IoError,
    };
}

fn triggerEvent(erased_self: *DunstblickUI.FeedbackInterface.ErasedSelf, event: protocol.EventID, widget: protocol.WidgetName) DunstblickUI.FeedbackInterface.Error!void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), erased_self));

    var backing_buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&backing_buf);

    var buffer = protocol.beginApplicationCommandEncoding(stream.writer(), .eventCallback) catch |err| return mapEncodeError(err);
    buffer.writeID(@enumToInt(event)) catch |err| return mapEncodeError(err);
    buffer.writeID(@enumToInt(widget)) catch |err| return mapEncodeError(err);

    self.client.sendMessage(stream.getWritten()) catch |err| return mapSendError(err);
}

fn triggerPropertyChanged(erased_self: *DunstblickUI.FeedbackInterface.ErasedSelf, oid: protocol.ObjectID, name: protocol.PropertyName, value: DunstblickUI.Value) DunstblickUI.FeedbackInterface.Error!void {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), erased_self));

    if (oid == .invalid)
        return;
    if (name == .invalid)
        return;

    var backing_buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&backing_buf);

    var buffer = protocol.beginApplicationCommandEncoding(stream.writer(), .propertyChanged) catch |err| return mapEncodeError(err);
    buffer.writeID(@enumToInt(oid)) catch |err| return mapEncodeError(err);
    buffer.writeID(@enumToInt(name)) catch |err| return mapEncodeError(err);
    value.serialize(&buffer, true) catch |err| return mapEncodeError(err);

    self.client.sendMessage(stream.getWritten()) catch |err| return mapSendError(err);
}

pub fn update(self: *Self, dt: f32) !void {
    _ = dt;
    switch (self.state) {
        .unconnected => {
            // make socket non-blocking for connect

        },
        .socket_connecting => {
            // wait for the callback
        },
        .protocol_connecting => {
            // we're waiting for the connection
        },
        .connected => {
            // try self.user_interface.update(dt);
            // we're done now :)
        },
        .faulted => {},
    }
}

pub fn resize(self: *Self, size: Size) !void {
    //
    self.screen_size = size;
}

pub fn processUserInterface(self: *Self, rectangle: zero_graphics.Rectangle, ui: zero_graphics.UserInterface.Builder) zero_graphics.UserInterface.Builder.Error!void {
    if (self.state == .connected) {
        self.user_interface.processUserInterface(rectangle, ui) catch |err| switch (err) {
            error.ResourceMismatch => {
                // TODO: Drop connection here?!
                @panic("unhandled error!");
            },
            error.InvalidLayout => {
                // TODO: Drop connection here?!
                @panic("unhandled error!");
            },
            else => |e| return e,
        };
    }

    // const center_rect = rectangle.centered(200, 400);

    // var temp_string_buffer: [256]u8 = undefined;

    // try ui.panel(center_rect, .{});

    // var layout = zero_graphics.UserInterface.VerticalStackLayout.init(center_rect.shrink(4));

    // try ui.label(layout.get(24), "Remote Application", .{ .horizontal_alignment = .center });

    // try ui.label(layout.get(24), std.fmt.bufPrint(&temp_string_buffer, "End Point: {}", .{self.remote_end_point}) catch "<oom>", .{});
    // try ui.label(layout.get(24), "Resources:", .{});
    // {
    //     var it = self.resources.iterator();

    //     while (it.next()) |res| {
    //         try ui.label(layout.get(20), std.fmt.bufPrint(&temp_string_buffer, "RES {}: {:.3} of {s}", .{
    //             @enumToInt(res.key_ptr.*),
    //             std.fmt.fmtIntSizeBin(res.value_ptr.data.items.len),
    //             @tagName(res.value_ptr.kind),
    //         }) catch "<oom>", .{});
    //     }
    // }
}

fn disconnect(self: *Self, quit_message: ?[]const u8) void {
    if (self.socket) |*sock| {
        if (self.client.isConnectionEstablished()) {
            if (quit_message) |msg| {
                // TODO: Send proper quit message
                self.client.sendMessage(msg) catch {};
            }
        }

        self.client.deinit();

        self.discovery.socket_set.remove(sock.*);

        sock.close();
        self.state = .faulted;
    }
    self.socket = null;
}

pub fn close(self: *Self) void {
    self.disconnect("User closed the connection.");
    self.instance.status = .{ .exited = "DE killed me" };
}

const Interface = struct {
    pub fn update(instance: *ApplicationInstance, dt: f32) ApplicationInstance.Interface.UpdateError!void {
        const self = @fieldParentPtr(Self, "instance", instance);
        self.update(dt) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.IoError,
        };
    }

    pub fn resize(instance: *ApplicationInstance, size: Size) ApplicationInstance.Interface.ResizeError!void {
        const self = @fieldParentPtr(Self, "instance", instance);
        try self.resize(size);
    }

    pub fn processUserInterface(instance: *ApplicationInstance, rectangle: zero_graphics.Rectangle, ui: zero_graphics.UserInterface.Builder) zero_graphics.UserInterface.Builder.Error!void {
        const self = @fieldParentPtr(Self, "instance", instance);
        try self.processUserInterface(rectangle, ui);
    }

    pub fn close(instance: *ApplicationInstance) void {
        const self = @fieldParentPtr(Self, "instance", instance);
        self.close();
    }

    pub fn deinit(instance: *ApplicationInstance) void {
        const self = @fieldParentPtr(Self, "instance", instance);
        self.deinit();
    }
};

const std = @import("std");
const xnet = @import("network");
const protocol = @import("dunstblick-protocol");

const log = std.log.scoped(.dunstblick);

/// Enumeration of reasons why a connection to an application could have closed.
pub const DisconnectReason = protocol.DisconnectReason;
pub const ClientCapabilities = protocol.ClientCapabilities;
pub const Size = protocol.Size;
pub const ResourceID = protocol.ResourceID;
pub const ObjectID = protocol.ObjectID;
pub const EventID = protocol.EventID;
pub const PropertyName = protocol.PropertyName;
pub const ResourceKind = protocol.ResourceKind;
pub const WidgetName = protocol.WidgetName;
pub const Type = protocol.Type;
pub const Value = protocol.Value;
pub const String = protocol.String;
pub const ObjectList = protocol.ObjectList;
pub const SizeList = protocol.SizeList;
pub const Margins = protocol.Margins;
pub const Color = protocol.Color;
pub const Point = protocol.Point;

pub const DunstblickError = error{
    OutOfMemory,
    NetworkError,
    OutOfRange,
    EndOfStream,
    ResourceNotFound,
    NoSpaceLeft,
    ProtocolViolation,
};

const NetworkError = error{
    InsufficientBytes,
    UnsupportedAddressFamily,
    SystemResources,
    Unexpected,
    ConnectionAborted,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    ProtocolFailure,
    BlockedByFirewall,
    WouldBlock,
    NotConnected,
    AccessDenied,
    FastOpenAlreadyInProgress,
    ConnectionResetByPeer,
    MessageTooBig,
    BrokenPipe,
    ConnectionRefused,
    InputOutput,
    IsDir,
    OperationAborted,
    PermissionDenied,
    NetworkSubsystemFailed,
    SocketNotBound,
    SocketNotConnected,
    AddressNotAvailable,
    NotDir,
    FileNotFound,
    NameTooLong,
    SymLinkLoop,
    AddressFamilityNotSupported,
    FileDescriptorNotASocket,
    NetworkUnreachable,
    AddressFamilyNotSupported,
    SocketNotListening,
    OperationNotSupported,
    OutOfMemory,
};

fn mapNetworkError(value: NetworkError) DunstblickError {
    log.debug("network error: {}:", .{value});
    return switch (value) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.NetworkError,
    };
}

fn mapSendError(value: protocol.tcp.ServerStateMachine(xnet.Socket.Writer).SendError) DunstblickError {
    log.debug("network send error: {}:", .{value});
    return switch (value) {
        error.OutOfMemory => error.OutOfMemory,
        error.SliceOutOfRange => error.OutOfRange,
        else => error.NetworkError,
    };
}

fn mapReceiveError(value: protocol.tcp.ServerStateMachine(xnet.Socket.Writer).ReceiveError) DunstblickError {
    log.debug("network receive error: {}:", .{value});

    return switch (value) {
        error.OutOfMemory => error.OutOfMemory,
        error.UnexpectedData => error.ProtocolViolation,
        error.InvalidData => error.ProtocolViolation,
        error.UnsupportedVersion => error.ProtocolViolation,
        error.ProtocolViolation => error.ProtocolViolation,
        else => |e| (e),
    };
}

fn mapDecodeError(value: DecodeError) DunstblickError {
    log.debug("network decode error: {}:", .{value});

    return switch (value) {
        error.OutOfMemory => error.OutOfMemory,
        error.NotSupported => error.ProtocolViolation,
        error.UnknownPacket => error.ProtocolViolation,
        error.EndOfStream => error.ProtocolViolation,
        error.Overflow => error.ProtocolViolation,
    };
}

const DecodeError = error{
    OutOfMemory,
    NotSupported,
    UnknownPacket,
    EndOfStream,
    Overflow,
};

fn extractString(str: []const u8) []const u8 {
    for (str) |chr, i| {
        if (chr == 0)
            return str[0..i];
    }
    return str;
}

const StoredResource = struct {
    const Self = @This();

    id: protocol.ResourceID,
    type: protocol.ResourceKind,
    hash: protocol.ResourceHash,
    data: []u8, // allocated with Application.allocator

    fn updateHash(self: *Self) void {
        self.hash = protocol.computeResourceHash(self.data);
    }
};

pub const ConnectedEvent = struct {
    /// The newly created connection.
    connection: *Connection,

    /// Current screen size of the display client.
    screenSize: Size,

    /// Bitmask containing all available capabilities of the display client.
    capabilities: std.EnumSet(ClientCapabilities),
};

pub const DisconnectedEvent = struct {
    /// The connection that is about to be closed.
    connection: *Connection,

    /// The reason why the  display client is disconnected
    reason: DisconnectReason,
};

pub const WidgetEvent = struct {
    /// the display client that triggered the event.
    connection: *Connection,
    /// The id of the event that was triggered. This ID is specified in the UI layout.
    event: protocol.EventID,
    /// The name of the widget that triggered the event.
    caller: protocol.WidgetName,
};

pub const PropertyChangedEvent = struct {
    /// the display client that changed the event.
    connection: *Connection,
    /// The object handle where the property was changed
    object: protocol.ObjectID,
    /// The name of the property that was changed
    property: protocol.PropertyName,
    /// The value of the property
    value: Value,
};

pub const EventType = std.meta.Tag(Event);

pub const Event = union(enum) {
    /// A new display client has connected to the server.
    connected: ConnectedEvent,

    /// A display client has disconnected
    disconnected: DisconnectedEvent,

    /// A widget in a connection triggered an event.
    widget_event: WidgetEvent,

    /// A property of a remote object was changed
    property_changed: PropertyChangedEvent,
};

/// A connection that was established by a display client.
/// Use these to interact with your clients.
pub const Connection = struct {
    const Self = @This();

    const PacketQueue = std.atomic.Queue([]const u8);

    mutex: std.Thread.Mutex,

    sock: xnet.Socket,
    remote: xnet.EndPoint,

    disconnect_reason: ?DisconnectReason = null,

    client_capabilities: std.EnumSet(ClientCapabilities),
    screen_resolution: Size,

    provider: *Application,

    server: protocol.tcp.ServerStateMachine(xnet.Socket.Writer),

    user_data_pointer: ?*anyopaque,

    fn init(provider: *Application, sock: xnet.Socket, endpoint: xnet.EndPoint) Connection {
        log.debug("connection from {}", .{endpoint});
        return Connection{
            .mutex = .{},
            .sock = sock,
            .remote = endpoint,
            .provider = provider,
            .client_capabilities = undefined,
            .screen_resolution = undefined,
            .user_data_pointer = null,
            .server = protocol.tcp.ServerStateMachine(xnet.Socket.Writer).init(provider.allocator, sock.writer()),
        };
    }

    fn deinit(self: *Self) void {
        log.debug("connection lost to {}", .{self.remote});
        self.server.deinit();
        self.sock.close();
    }

    fn drop(self: *Self, reason: DisconnectReason) void {
        if (self.disconnect_reason != null)
            return; // already dropped
        self.disconnect_reason = reason;
        log.debug("dropped connection to {}: {}", .{ self.remote, reason });
    }

    /// Shoves data from the display server into the connection.
    fn pushData(self: *Self, blob: []const u8) !void {
        errdefer self.drop(DisconnectReason.invalid_data);

        var offset: usize = 0;
        while (offset < blob.len) {
            const receive_info = try self.server.pushData(blob[offset..]);
            offset += receive_info.consumed;
            if (receive_info.event) |event| {
                switch (event) {
                    .initiate_handshake => |info| {
                        const auth_action = try self.server.acknowledgeHandshake(.{
                            .requires_username = false,
                            .requires_password = false,
                            .rejects_username = info.has_username, // reject both username and password if present
                            .rejects_password = info.has_password, // reject both username and password if present
                        });

                        if (auth_action != .send_auth_result)
                            return error.ProtocolViolation;

                        try self.server.sendAuthenticationResult(.success, false);
                    },

                    .authenticate_info => |info| {
                        _ = info;
                        @panic("not implemented yet");
                    },

                    .connect_header => |info| {
                        self.client_capabilities = info.capabilities;
                        self.screen_resolution.width = info.screen_width;
                        self.screen_resolution.height = info.screen_height;

                        {
                            self.provider.resource_lock.lock();
                            defer self.provider.resource_lock.unlock();

                            var resource_headers = std.ArrayList(protocol.tcp.ConnectResponseItem).init(self.provider.allocator);
                            defer resource_headers.deinit();

                            try resource_headers.ensureTotalCapacity(self.provider.resources.count());

                            var iter = self.provider.resources.iterator();
                            while (iter.next()) |kv| {
                                const resource = kv.value_ptr;
                                resource_headers.appendAssumeCapacity(protocol.tcp.ConnectResponseItem{
                                    .id = resource.id,
                                    .size = @truncate(u32, resource.data.len),
                                    .type = resource.type,
                                    .hash = resource.hash,
                                });
                            }

                            try self.server.sendConnectResponse(resource_headers.items);
                        }
                    },
                    .resource_request => |info| {
                        self.provider.resource_lock.lock();
                        defer self.provider.resource_lock.unlock();

                        for (info.requested_resources) |res_id| {
                            if (self.provider.resources.getEntry(res_id)) |entry| {
                                try self.server.sendResourceHeader(res_id, entry.value_ptr.data);
                            } else {
                                return error.ProtocolViolation;
                            }
                        }
                    },
                    .message => |packet| {
                        try self.decodePacket(packet);
                    },
                }
            }
        }
    }

    /// transmit a CommandBuffer synchronously
    /// @remarks self will lock the Connection internally,
    ///          so don't wrap self call into a mutex!
    fn send(self: *Self, packet: []const u8) DunstblickError!void {
        errdefer self.drop(.network_error);

        self.mutex.lock();
        defer self.mutex.unlock();

        self.server.sendMessage(packet) catch |err| return mapSendError(err);
    }

    fn decodePacket(self: *Self, packet: []const u8) DecodeError!void {
        var reader = protocol.Decoder.init(packet);

        const msgtype = @intToEnum(protocol.ApplicationCommand, try reader.readByte());

        switch (msgtype) {
            .eventCallback => {
                const id = @intToEnum(protocol.EventID, try reader.readVarUInt());
                const widget = @intToEnum(protocol.WidgetName, try reader.readVarUInt());

                const event = try self.provider.createEvent();
                event.event = Event{
                    .widget_event = WidgetEvent{
                        .connection = self,
                        .event = id,
                        .caller = widget,
                    },
                };
                self.provider.enqueueEvent(event);
            },
            .propertyChanged => {
                const obj_id = @intToEnum(protocol.ObjectID, try reader.readVarUInt());
                const property = @intToEnum(protocol.PropertyName, try reader.readVarUInt());
                const value_type = @intToEnum(protocol.Type, try reader.readByte());

                const event = try self.provider.createEvent();
                errdefer self.provider.freeEvent(event);

                const value = try Value.deserialize(&event.memory.allocator, value_type, &reader);

                event.event = Event{
                    .property_changed = PropertyChangedEvent{
                        .connection = self,
                        .object = obj_id,
                        .property = property,
                        .value = value,
                    },
                };
                self.provider.enqueueEvent(event);
            },
            _ => {
                log.err("Received {} bytes of an unknown message type {}", .{ packet.len, msgtype });
                return error.UnknownPacket;
            },
        }
    }

    fn receiveData(self: *Self) !void {
        var buffer: [4096]u8 = undefined;
        const len = self.sock.receive(&buffer) catch |err| return mapNetworkError(err);
        if (len == 0)
            return self.drop(.quit);

        self.pushData(buffer[0..len]) catch |err| return switch (err) {
            error.UnexpectedData, error.InvalidData, error.UnsupportedVersion, error.ProtocolViolation => |e| mapReceiveError(e),
            error.NotSupported, error.UnknownPacket, error.EndOfStream, error.Overflow => |e| mapDecodeError(e),
            else => |e| mapSendError(e),
        };
    }

    // User API

    /// Closes the connection to the client. `actual_reason` will be displayed to the user if possible.
    pub fn close(self: *Self, actual_reason: []const u8) void {
        {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.disconnect_reason != null)
                return;

            self.disconnect_reason = .shutdown;
        }

        var buffer = std.ArrayList(u8).init(self.provider.allocator);
        defer buffer.deinit();

        var encoder = protocol.beginDisplayCommandEncoding(buffer.writer(), .disconnect) catch return;
        encoder.writeString(actual_reason) catch return;

        self.send(buffer.items) catch return;
    }

    /// Sets the current view.
    /// This view must have been uploaded with @ref dunstblick_UploadResource earlier.
    pub fn setView(self: *Self, id: ResourceID) DunstblickError!void {
        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .setView);

        try buffer.writeID(@enumToInt(id));
        try self.send(stream.getWritten());
    }

    /// Sets the current binding root.
    /// This object will serve as the root of all binding functions and will provide
    /// the root logic for the current view.
    pub fn setRoot(self: *Self, id: ObjectID) DunstblickError!void {
        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .setRoot);

        try buffer.writeID(@enumToInt(id));
        try self.send(stream.getWritten());
    }

    /// Starts an object change. This is similar to a SQL transaction:
    /// - the change process is initiated
    /// - changes are made to an object handle
    /// - the process is either commited or cancelled.
    ///
    /// @returns Handle to the object that should be updated. Commit or cancel this handle to finalize this transaction.
    /// @see dunstblick_CommitObject, dunstblick_CancelObject, dunstblick_SetObjectProperty
    pub fn beginChangeObject(self: *Self, id: ObjectID) !*Object {
        var object = try self.provider.allocator.create(Object);
        errdefer self.provider.allocator.destroy(object);

        object.* = try Object.init(self);
        errdefer object.deinit();

        var enc = protocol.makeEncoder(object.commandbuffer.writer());

        try enc.writeID(@enumToInt(id));

        return object;
    }

    /// Removes a previously uploaded object.
    pub fn removeObject(self: *Self, id: ObjectID) DunstblickError!void {
        var backing_buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .setRoot);

        try buffer.writeID(@enumToInt(id));
        try self.send(stream.getWritten());
    }

    /// Moves a given range in a list property.
    /// This action is currently not implemented due to underspecification.
    pub fn moveRange(self: *Self, object: ObjectID, name: PropertyName, indexFrom: u32, indexTo: u32, count: u32) DunstblickError!void {
        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .moveRange);

        try buffer.writeID(@enumToInt(object));
        try buffer.writeID(@enumToInt(name));
        try buffer.writeVarUInt(indexFrom);
        try buffer.writeVarUInt(indexTo);
        try buffer.writeVarUInt(count);

        try self.send(stream.getWritten());
    }

    /// Sets a property on the given object.
    /// The third parameter depends on the given type parameter.
    pub fn setProperty(self: *Self, object: ObjectID, name: PropertyName, value: Value) DunstblickError!void {
        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .setProperty);

        try buffer.writeID(@enumToInt(object));
        try buffer.writeID(@enumToInt(name));
        try value.serialize(&buffer, true);

        try self.send(stream.getWritten());
    }

    /// Clears a list property of an object.
    /// This action will remove all object references from an objectlist property.
    pub fn clear(self: *Self, object: ObjectID, name: PropertyName) DunstblickError!void {
        var backing_buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .clear);

        try buffer.writeID(@enumToInt(object));
        try buffer.writeID(@enumToInt(name));

        try self.send(stream.getWritten());
    }

    /// Inserts a given range of object references into a list property.
    pub fn insertRange(self: *Self, object: ObjectID, name: PropertyName, index: u32, values: []const ObjectID) DunstblickError!void {
        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .insertRange);

        try buffer.writeID(@enumToInt(object));
        try buffer.writeID(@enumToInt(name));
        try buffer.writeVarUInt(index);
        try buffer.writeVarUInt(@intCast(u32, values.len));

        for (values) |id| {
            try buffer.writeID(@enumToInt(id));
        }

        try self.send(stream.getWritten());
    }

    /// Removes a given range from a list property.
    pub fn removeRange(self: *Self, object: ObjectID, name: PropertyName, index: u32, count: u32) DunstblickError!void {
        var backing_buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .removeRange);
        try buffer.writeID(@enumToInt(object));
        try buffer.writeID(@enumToInt(name));
        try buffer.writeVarUInt(index);
        try buffer.writeVarUInt(count);

        try self.send(stream.getWritten());
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Connection({})", .{self.sock.getLocalEndPoint()});
    }
};

pub const Application = struct {
    const Self = @This();

    const ResourceMap = std.AutoHashMap(protocol.ResourceID, StoredResource);

    const ConnectionList = std.TailQueue(Connection);
    const ConnectionNode = ConnectionList.Node;

    const AppEvent = struct {
        /// Stores all memory related to that event
        memory: std.heap.ArenaAllocator,

        event: Event,
    };

    const EventQueue = std.TailQueue(AppEvent);
    const EventNode = EventQueue.Node;

    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    multicast_sock: xnet.Socket,
    tcp_sock: xnet.Socket,
    discovery_name: []const u8, // owned

    app_description: ?[]const u8, // owned
    app_icon: ?[]const u8, // owned

    tcp_listener_ep: xnet.EndPoint,

    resource_lock: std.Thread.Mutex,
    resources: ResourceMap,

    pending_connections: ConnectionList,
    established_connections: ConnectionList,

    socket_set: xnet.SocketSet,

    // TODO: Implement event queue stuff here

    event_arena: std.heap.ArenaAllocator,

    /// Stores a ordered list of events that will be returned by `pollEvent()`
    event_queue: EventQueue,

    /// Stores a list of events that can be recycled. Events in here are `undefined`,
    /// but provide a already-allocated memory for less allocation pressure.
    event_stash: EventQueue,

    /// The last event that was returned to the user. Must be freed in the next call 
    /// of `pollEvent()`.
    current_user_event: ?*EventNode,

    /// Creates a new application that is visible to the network.
    pub fn open(
        allocator: std.mem.Allocator,
        /// The name that is shown to the discovering clients.
        discovery_name: []const u8,
        /// Optional description of the application, utf-8 encoded, limited to 256 byte.
        app_description: ?[]const u8,
        /// Optional TVG icon, limited to 512 byte.
        app_icon: ?[]const u8,
    ) !Self {
        if (app_description != null and app_description.?.len > protocol.udp.DiscoverResponse.ShortDescription.max_length)
            return error.DescriptionTooLong;
        if (app_icon != null and app_icon.?.len > protocol.udp.DiscoverResponse.IconDescription.max_length)
            return error.IconTooLong;
        var provider = Self{
            .mutex = .{},
            .resource_lock = .{},
            .allocator = allocator,

            .resources = ResourceMap.init(allocator),

            .pending_connections = .{},
            .established_connections = .{},

            .socket_set = try xnet.SocketSet.init(allocator),

            .event_arena = std.heap.ArenaAllocator.init(allocator),
            .event_queue = .{},
            .event_stash = .{},
            .current_user_event = null,

            // will be initialized in sequence:
            .discovery_name = undefined,
            .app_description = null,
            .app_icon = null,

            .tcp_sock = undefined,
            .multicast_sock = undefined,
            .tcp_listener_ep = undefined,
        };
        errdefer provider.resources.deinit();
        errdefer provider.event_arena.deinit();

        provider.discovery_name = try allocator.dupe(u8, discovery_name);
        errdefer allocator.free(provider.discovery_name);

        provider.app_description = if (app_description) |text| try allocator.dupe(u8, text) else null;
        errdefer if (provider.app_description) |ptr| allocator.free(ptr);

        provider.app_icon = if (app_icon) |data| if (data.len > 0) try allocator.dupe(u8, data) else null else null;
        errdefer if (provider.app_icon) |ptr| allocator.free(ptr);

        // Initialize TCP socket:
        provider.tcp_sock = try xnet.Socket.create(.ipv4, .tcp);
        errdefer provider.tcp_sock.close();

        try provider.tcp_sock.enablePortReuse(true);
        try provider.tcp_sock.bindToPort(0);
        try provider.tcp_sock.listen();

        provider.tcp_listener_ep = try provider.tcp_sock.getLocalEndPoint();

        // Initialize UDP socket:
        provider.multicast_sock = try xnet.Socket.create(.ipv4, .udp);
        errdefer provider.multicast_sock.close();

        try provider.multicast_sock.enablePortReuse(true);
        try provider.multicast_sock.bindToPort(protocol.udp.port);

        try provider.multicast_sock.joinMulticastGroup(.{
            .interface = xnet.Address.IPv4.any,
            .group = xnet.Address.IPv4.init(
                protocol.udp.multicast_group_v4[0],
                protocol.udp.multicast_group_v4[1],
                protocol.udp.multicast_group_v4[2],
                protocol.udp.multicast_group_v4[3],
            ),
        });

        log.debug("provider ready at {}", .{try provider.tcp_sock.getLocalEndPoint()});

        return provider;
    }

    /// Closes the application and all connections.
    pub fn close(self: *Self) void {
        {
            var iter = self.established_connections.first;
            while (iter) |item| {
                var next = item.next;
                defer iter = next;

                item.data.close("The provider has been shut down.");
                item.data.deinit();
                self.allocator.destroy(item);
            }
        }
        {
            var iter = self.pending_connections.first;
            while (iter) |item| {
                var next = item.next;
                defer iter = next;

                item.data.deinit();
                self.allocator.destroy(item);
            }
        }

        // Free all active events
        {
            var iter = self.event_queue.first;
            while (iter) |item| {
                iter = item.next;
                item.data.memory.deinit();
            }
        }

        // Contains all events in both event_queue and event_stash
        self.event_arena.deinit();

        self.resources.deinit();
        self.tcp_sock.close();
        self.multicast_sock.close();
        self.allocator.free(self.discovery_name);
        if (self.app_description) |text| self.allocator.free(text);
        if (self.app_icon) |data| self.allocator.free(data);
        self.socket_set.deinit();
    }

    /// Pumps network data, calls connection events and disconnect/connect callbacks.
    /// Call this function continuously to provide a fluent user interaction
    /// and prevent network timeouts.
    /// This function will pump events for up to `timeout` nanoseconds.
    pub fn pumpEvents(self: *Self, timeout: ?u64) DunstblickError!void {
        self.socket_set.clear();

        try self.socket_set.add(self.multicast_sock, .{ .read = true, .write = false });
        try self.socket_set.add(self.tcp_sock, .{ .read = true, .write = false });

        {
            var iter = self.pending_connections.first;
            while (iter) |node| : (iter = node.next) {
                try self.socket_set.add(node.data.sock, .{ .read = true, .write = true });
            }
        }
        {
            var iter = self.established_connections.first;
            while (iter) |node| : (iter = node.next) {
                try self.socket_set.add(node.data.sock, .{ .read = true, .write = false });
            }
        }

        _ = xnet.waitForSocketEvent(&self.socket_set, timeout) catch |err| return mapNetworkError(err);

        {
            var iter = self.pending_connections.first;
            while (iter) |item| : (iter = item.next) {
                if (self.socket_set.isFaulted(item.data.sock))
                    item.data.drop(.network_error);
            }
        }
        {
            var iter = self.established_connections.first;
            while (iter) |item| : (iter = item.next) {
                if (self.socket_set.isFaulted(item.data.sock))
                    item.data.drop(.network_error);
            }
        }

        // REQUIRED send_data must be called before push_data:
        // Sending is not allowed to be called on established connections,
        // but receiving a frame of "i don't require resources" will
        // switch the connection in READY state without having the need of
        // ever sending data.

        // FIRST THIS
        // {
        //     var iter = self.pending_connections.first;
        //     while (iter) |item| : (iter = item.next) {
        //         if (item.data.disconnect_reason != null)
        //             continue;

        //         if (self.socket_set.isReadyWrite(item.data.sock)) {
        //             item.data.sendData() catch item.data.drop(.invalid_data);
        //         }
        //     }
        // }

        // THEN THIS
        {
            var iter = self.pending_connections.first;
            while (iter) |item| : (iter = item.next) {
                if (item.data.disconnect_reason != null)
                    continue;
                if (self.socket_set.isReadyRead(item.data.sock)) {
                    try item.data.receiveData();
                }
            }
        }
        {
            var iter = self.established_connections.first;
            while (iter) |item| : (iter = item.next) {
                if (item.data.disconnect_reason != null)
                    continue;
                if (self.socket_set.isReadyRead(item.data.sock)) {
                    try item.data.receiveData();
                }
            }
        }

        if (self.socket_set.isReadyRead(self.multicast_sock)) {
            var message: protocol.udp.Message = undefined;

            if (self.multicast_sock.receiveFrom(std.mem.asBytes(&message))) |msg| {
                if (msg.numberOfBytes < @sizeOf(protocol.udp.Header)) {
                    log.err("udp message too small…", .{});
                } else {
                    if (std.mem.eql(u8, &message.header.magic, &protocol.udp.magic)) {
                        switch (message.header.type) {
                            .discover => {
                                if (msg.numberOfBytes >= @sizeOf(protocol.udp.Discover)) {
                                    var buffer: [protocol.udp.DiscoverResponse.buffer_size]u8 align(@alignOf(protocol.udp.DiscoverResponse)) = undefined;
                                    const response = @ptrCast(*protocol.udp.DiscoverResponse, &buffer);
                                    response.* = .{
                                        .features = .{
                                            .has_description = (self.app_description != null),
                                            .has_icon = (self.app_icon != null),
                                            .requires_auth = false,
                                            .wants_username = false,
                                            .wants_password = false,
                                            .is_encrypted = false,
                                        },
                                        .tcp_port = self.tcp_listener_ep.port,
                                        .display_name = undefined,
                                    };
                                    response.setName(self.discovery_name) catch @panic("Application name too long!");

                                    if (response.getDescriptionPtr()) |ptr| {
                                        ptr.set(self.app_description.?) catch @panic("Application description too long!");
                                    }
                                    if (response.getIconPtr()) |ptr| {
                                        ptr.set(self.app_icon.?) catch @panic("Application icon too long!");
                                    }

                                    // log.debug("response to {}", .{msg.sender});

                                    const length = response.getTotalPacketLength();
                                    // log.debug("sendTo({}, '{}')", .{
                                    //     msg.sender,
                                    //     std.fmt.fmtSliceHexLower(buffer[0..length]),
                                    // });
                                    if (self.multicast_sock.sendTo(msg.sender, buffer[0..length])) |sendlen| {
                                        if (sendlen < length) {
                                            log.err("expected to send {} bytes, got {}", .{
                                                length,
                                                sendlen,
                                            });
                                        }
                                    } else |err| {
                                        log.err("failed to send udp response: {}", .{err});
                                    }
                                } else {
                                    log.err("expected {} bytes, got {}", .{ @sizeOf(protocol.udp.Discover), msg.numberOfBytes });
                                }
                            },
                            .respond_discover => {
                                if (msg.numberOfBytes >= @sizeOf(protocol.udp.DiscoverResponse)) {
                                    log.debug("got udp response", .{});
                                } else {
                                    log.err("expected {} bytes, got {}", .{
                                        @sizeOf(protocol.udp.DiscoverResponse),
                                        msg.numberOfBytes,
                                    });
                                }
                            },

                            _ => |val| {
                                log.err("invalid packet type: {}", .{val});
                            },
                        }
                    } else {
                        log.err("Invalid packet magic: {X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{
                            message.header.magic[0],
                            message.header.magic[1],
                            message.header.magic[2],
                            message.header.magic[3],
                        });
                    }
                }
            } else |err| {
                log.err("failed to receive udp message: {}", .{err});
            }
        }
        if (self.socket_set.isReadyRead(self.tcp_sock)) {
            const socket = self.tcp_sock.accept() catch |err| return mapNetworkError(err);
            errdefer socket.close();

            const ep = socket.getRemoteEndPoint() catch |err| return mapNetworkError(err);

            const node = try self.allocator.create(ConnectionNode);
            errdefer self.allocator.destroy(node);

            node.* = .{ .data = Connection.init(self, socket, ep) };
            self.pending_connections.append(node);
        }

        // Close all pending connections that were dropped
        {
            var iter = self.pending_connections.first;
            while (iter) |item| {
                const next = item.next;
                defer iter = next;

                if (item.data.disconnect_reason != null) {
                    self.pending_connections.remove(item);
                    item.data.deinit();
                    self.allocator.destroy(item);
                }
            }
        }

        // Transfer all ready connections to established_connections
        {
            var iter = self.pending_connections.first;
            while (iter) |item| {
                const next = item.next;
                defer iter = next;

                if (item.data.server.isConnectionEstablished()) {
                    self.pending_connections.remove(item);

                    const event = try self.createEvent();
                    errdefer self.freeEvent(event);

                    event.event = Event{
                        .connected = ConnectedEvent{
                            .connection = &item.data,
                            // .clientName = try event.memory.allocator.dupeZ(u8, item.data.header.?.clientName),
                            // .password = try event.memory.allocator.dupeZ(u8, item.data.header.?.clientName),
                            .screenSize = item.data.screen_resolution,
                            .capabilities = item.data.client_capabilities,
                        },
                    };

                    self.enqueueEvent(event);

                    self.established_connections.append(item);
                }
            }
        }

        // Close all established connections that were dropped
        {
            var iter = self.established_connections.first;
            while (iter) |item| {
                const next = item.next;
                defer iter = next;

                if (item.data.disconnect_reason != null) {
                    const event = try self.createEvent();
                    errdefer self.freeEvent(event);

                    event.event = Event{
                        .disconnected = DisconnectedEvent{
                            .connection = &item.data,
                            .reason = item.data.disconnect_reason.?,
                        },
                    };

                    self.enqueueEvent(event);

                    self.established_connections.remove(item);

                    // item.data.deinit();
                    // self.allocator.destroy(item);
                }
            }
        }
    }

    /// Allocates a new event and returns it. Initializes the arena, but not the event pointer.
    fn createEvent(self: *Self) !*AppEvent {
        const node = if (self.event_stash.pop()) |node|
            node
        else
            try self.event_arena.allocator.create(EventNode);

        node.* = EventNode{
            .data = AppEvent{
                .memory = std.heap.ArenaAllocator.init(self.allocator),
                .event = undefined,
            },
        };

        return &node.data;
    }

    /// The event will already be enqueued in the `event_queue`.
    fn enqueueEvent(self: *Self, event: *AppEvent) void {
        const node = @fieldParentPtr(EventNode, "data", event);
        self.event_queue.append(node);
    }

    /// Returns a event into the stash and frees its resources.
    fn freeEvent(self: *Self, event: *AppEvent) void {
        const node = @fieldParentPtr(EventNode, "data", event);

        event.memory.deinit();
        event.* = undefined;

        self.event_stash.append(node);
    }

    /// Pumps events until either `timeout` nanoseconds have elapsed or at least a single event has happened.
    /// Will return a pointer to the event or `null` when no event happened.
    pub fn pollEvent(self: *Self, timeout: ?u64) !?*Event {

        // Check if we returned an event to the user earlier
        if (self.current_user_event) |event| {
            self.current_user_event = null;

            if (event.data.event == .disconnected) {
                const connection = event.data.event.disconnected.connection;
                connection.deinit();

                const node = @fieldParentPtr(ConnectionNode, "data", connection);
                self.allocator.destroy(node);
            }

            self.freeEvent(&event.data);
        }

        if (self.event_queue.popFirst()) |event| {
            std.debug.assert(self.current_user_event == null);
            self.current_user_event = event;
            return &event.data.event;
        }

        while (true) {

            // event queue is empty, poll for more events from the network
            try self.pumpEvents(timeout);

            if (self.event_queue.popFirst()) |event| {
                std.debug.assert(self.current_user_event == null);
                self.current_user_event = event;
                return &event.data.event;
            }
            if (timeout != null)
                return null;
        }
    }

    // Public API

    /// Adds a resource to the UI system.
    /// The resource will be hashed and stored until the provider is shut down
    /// or the the resource is removed again.
    /// Resources in the storage will be uploaded to a display client on connection
    /// and newly added resources will also be sent to all currently connected display
    /// clients.
    pub fn addResource(self: *Self, id: protocol.ResourceID, kind: protocol.ResourceKind, data: []const u8) DunstblickError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var cloned_data = try std.mem.dupe(self.allocator, u8, data);
        errdefer self.allocator.free(cloned_data);

        const result = try self.resources.getOrPut(id);

        std.debug.assert(result.key_ptr.* == id);
        if (result.found_existing) {
            std.debug.assert(result.value_ptr.id == id);
            self.allocator.free(result.value_ptr.data);
        } else {
            result.value_ptr.id = id;
        }
        result.value_ptr.type = @intToEnum(protocol.ResourceKind, @enumToInt(kind));
        result.value_ptr.data = cloned_data;
        result.value_ptr.updateHash();

        // TODO: Forward the result to all connected clients.
    }

    /// Deletes a resource from the UI system.
    /// Already uploaded resources will stay uploaded until the resource ID is
    /// used again, but newly connected display clients will not receive the
    /// resource anymore.
    pub fn removeResource(self: *Self, id: protocol.ResourceID) DunstblickError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.resources.fetchRemove(id)) |item| {
            self.allocator.free(item.value.data);
        }
    }
};

/// Temporary handle to a object structure.
/// Allows batch-uploads to objects on the display client.
pub const Object = struct {
    const Self = @This();
    connection: *Connection,
    commandbuffer: std.ArrayList(u8),

    fn init(con: *Connection) !Self {
        var object = Self{
            .connection = con,
            .commandbuffer = std.ArrayList(u8).init(con.provider.allocator),
        };

        var enc = protocol.makeEncoder(object.commandbuffer.writer());
        try enc.writeByte(@enumToInt(protocol.DisplayCommand.addOrUpdateObject));

        return object;
    }

    fn deinit(self: Self) void {
        self.commandbuffer.deinit();
    }

    /// Sets a property on the given object.
    /// The third parameter depends on the given type parameter.
    pub fn setProperty(self: *Self, name: protocol.PropertyName, value: Value) DunstblickError!void {
        var enc = protocol.makeEncoder(self.commandbuffer.writer());

        try enc.writeEnum(@intCast(u8, @enumToInt(std.meta.activeTag(value))));
        try enc.writeID(@enumToInt(name));
        try value.serialize(&enc, false);
    }

    /// The object will either be added to the list of objects
    /// or, if an object with the same ID already exists, will replace that object.
    /// The new object will only have the properties set in this transaction,
    /// All old properties will be *removed*.
    /// The object will be released in this function. the handle is not valid after this function is called.
    pub fn commit(self: *Self) DunstblickError!void {
        defer self.cancel(); // self will free the memory

        var enc = protocol.makeEncoder(self.commandbuffer.writer());
        try enc.writeEnum(0);

        try self.connection.send(self.commandbuffer.items);
    }

    /// Closes the object and cancels the update process.
    /// The object will be released in this function. the handle is not valid after this function is called.
    pub fn cancel(self: *Self) void {
        self.commandbuffer.deinit();
        self.connection.provider.allocator.destroy(self);
    }
};

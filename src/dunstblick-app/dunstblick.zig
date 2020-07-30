const std = @import("std");
const xnet = @import("network");
const protocol = @import("dunstblick-protocol");

pub const DisconnectReason = enum(u32) {
    /// The user closed the connection.
    quit = 0,

    /// The connection was closed by a call to @ref dunstblick_CloseConnection.
    shutdown = 1,

    /// The display client did not respond for a longer time.
    timeout = 2,

    /// The network connection failed.
    network_error = 3,

    /// The client was forcefully disconnected for sending invalid data.
    invalid_data = 4,

    /// The protocol used by the display client is not compatible to this library.
    protocol_mismatch = 5,
};

pub const ClientCapabilities = protocol.ClientCapabilities;
pub const Size = extern struct {
    width: u32,
    height: u32,
};
pub const ResourceID = protocol.ResourceID;
pub const ObjectID = protocol.ObjectID;
pub const EventID = protocol.EventID;
pub const PropertyName = protocol.PropertyName;
pub const Value = protocol.Value;
pub const ResourceKind = protocol.ResourceKind;
pub const WidgetName = protocol.WidgetName;

/// A callback that is called whenever a new display client has successfully
/// connected to the display provider.
/// It's possible to disconnect the client in this callback, the @ref dunstblick_DisconnectedCallback
/// will be called as soon as this function returns.
pub const ConnectedCallback = fn (
    ///< The application to which the connection was established.
    application: *Application,
    ///< The newly created connection.
    connection: *Connection,
    ///< The name of the display client. If none is given, it's just `IP:port`
    clientName: [*:0]const u8,
    ///< The password that was passed by the user.
    password: [*:0]const u8,
    ///< Current screen size of the display client.
    screenSize: Size,
    ///< Bitmask containing all available capabilities of the display client.
    capabilities: ClientCapabilities,
    ///< The user data pointer that was passed to @ref dunstblick_SetConnectedCallback.
    userData: ?*c_void,
) callconv(.C) void;

/// A callback that is called whenever a display client has disconnected
/// from the provider.
/// This callback is called for every disconnected client, even when the client is closed
/// in the @ref dunstblick_ConnectedCallback.
/// @remarks It is possible to query information about `connection`, but it's not possible
///          anymore to send any data to it.
pub const DisconnectedCallback = fn (
    ///< The application from which the connection was discnnected.
    application: *Application,
    /// The connection that is about to be closed.
    connection: *Connection,
    ///< The reason why the  display client is disconnected
    reason: DisconnectReason,
    ///< The user data pointer that was passed to @ref dunstblick_SetDisconnectedCallback.
    userData: ?*c_void,
) callconv(.C) void;

/// @brief A callback that is called whenever a display client triggers a event.
pub const EventCallback = fn (
    ///< the display client that triggered the event.
    connection: *Connection,
    ///< The id of the event that was triggered. This ID is specified in the UI layout.
    event: protocol.EventID,
    ///< The name of the widget that triggered the event.
    caller: protocol.WidgetName,
    ///< The user data pointer that was passed to @ref dunstblick_SetEventCallback.
    userData: ?*c_void,
) callconv(.C) void;

/// A callback that is called whenever a display client changed the property of an object.
pub const PropertyChangedCallback = fn (
    ///< the display client that changed the event.
    connection: *Connection,
    ///< The object handle where the property was changed
    object: protocol.ObjectID,
    ///< The name of the property that was changed
    property: protocol.PropertyName,
    ///< The value of the property
    value: *const protocol.Value,
    ///< The user data pointer that was passed to @ref dunstblick_SetPropertyChangedCallback.
    userData: ?*c_void,
) callconv(.C) void;

pub const DunstblickError = error{
    OutOfMemory,
    NetworkError,
    OutOfRange,
    EndOfStream,
    ResourceNotFound,
    NoSpaceLeft,
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
};

fn mapNetworkError(value: NetworkError) DunstblickError {
    std.log.debug(.dunstblick, "network error: {}:\n", .{value});
    switch (value) {
        else => |e| return error.NetworkError,
    }
}

fn extractString(str: []const u8) []const u8 {
    for (str) |chr, i| {
        if (chr == 0)
            return str[0..i];
    }
    return str;
}

const ConnectionHeader = struct {
    clientName: [:0]const u8,
    password: [:0]const u8,
    capabilities: ClientCapabilities,
};

const SipHash = [8]u8;

fn computeHash(data: []const u8) SipHash {
    var hash: SipHash = undefined;

    const key = "DUNSTBLICK Hash!";

    const int_hash = std.hash.SipHash64(3, 2).hash(key, data);

    std.mem.writeIntLittle(
        u64,
        &hash,
        int_hash,
    );

    return hash;
}

const StoredResource = struct {
    const Self = @This();

    id: protocol.ResourceID,
    type: protocol.ResourceKind,
    data: []u8, // allocated with Application.allocator
    hash: SipHash,

    fn updateHash(self: *Self) void {
        self.hash = computeHash(self.data);
    }
};

pub const Connection = struct {
    const Self = @This();

    const State = enum {
        READ_HEADER,
        READ_REQUIRED_RESOURCE_HEADER,
        READ_REQUIRED_RESOURCES,
        SEND_RESOURCES,
        READY,
    };

    const PacketQueue = std.atomic.Queue([]const u8);

    mutex: std.Mutex,

    sock: xnet.Socket,
    remote: xnet.EndPoint,

    state: State = .READ_HEADER,

    is_initialized: bool = false,
    disconnect_reason: ?DisconnectReason = null,

    header: ?ConnectionHeader,
    screen_resolution: Size,

    receive_buffer: std.ArrayList(u8),
    provider: *Application,

    ///< total number of resources required by the display client
    required_resource_count: usize,
    ///< ids of the required resources
    required_resources: std.ArrayList(protocol.ResourceID),
    ///< currently transmitted resource
    resource_send_index: usize,
    ///< current byte offset in the resource
    resource_send_offset: usize,

    user_data_pointer: ?*c_void,

    // FIX: #5920
    // Lock access to event in multithreaded scenarios!
    on_event: struct {
        function: ?EventCallback,
        user_data: ?*c_void,

        fn invoke(self: @This(), args: anytype) void {
            if (self.function) |function| {
                @call(.{}, function, args ++ .{self.user_data});
            } else {
                std.log.debug(.dunstblick, "callback does not exist!\n", .{});
            }
        }
    },

    // FIX: #5920
    // Lock access to event in multithreaded scenarios!
    on_property_changed: struct {
        function: ?PropertyChangedCallback,
        user_data: ?*c_void,

        fn invoke(self: @This(), args: anytype) void {
            if (self.function) |function| {
                @call(.{}, function, args ++ .{self.user_data});
            } else {
                std.log.debug(.dunstblick, "callback does not exist!\n", .{});
            }
        }
    },

    fn init(provider: *Application, sock: xnet.Socket, endpoint: xnet.EndPoint) Connection {
        std.log.debug(.dunstblick, "connection from {}\n", .{endpoint});
        return Connection{
            .mutex = std.Mutex.init(),
            .sock = sock,
            .remote = endpoint,
            .provider = provider,
            .header = null,
            .screen_resolution = undefined,
            .receive_buffer = std.ArrayList(u8).init(provider.allocator),
            .required_resource_count = undefined,
            .required_resources = std.ArrayList(ResourceID).init(provider.allocator),
            .resource_send_index = undefined,
            .resource_send_offset = undefined,
            .user_data_pointer = null,
            .on_event = .{ .function = null, .user_data = null },
            .on_property_changed = .{ .function = null, .user_data = null },
        };
    }

    fn deinit(self: *Self) void {
        std.log.debug(.dunstblick, "connection lost to {}\n", .{self.remote});
        self.receive_buffer.deinit();

        self.sock.close();

        if (self.header) |hdr| {
            self.provider.allocator.free(hdr.password);
            self.provider.allocator.free(hdr.clientName);
        }

        self.required_resources.deinit();
    }

    fn drop(self: *Self, reason: DisconnectReason) void {
        if (self.disconnect_reason != null)
            return; // already dropped
        self.disconnect_reason = reason;
        std.log.debug(.dunstblick, "dropped connection to {}: {}\n", .{ self.remote, reason });
    }

    //! Shoves data from the display server into the connection.
    fn pushData(self: *Self, blob: []const u8) !void {
        const MAX_BUFFER_LIMIT = 5 * 1024 * 1024; // 5 MeBiByte

        if (self.receive_buffer.items.len + blob.len >= MAX_BUFFER_LIMIT) {
            return self.drop(.invalid_data);
        }

        try self.receive_buffer.appendSlice(blob);

        std.log.debug(.dunstblick, "read {} bytes from {} into buffer of {}\n", .{
            blob.len,
            self.remote,
            self.receive_buffer.items.len,
        });

        while (self.receive_buffer.items.len > 0) {
            const stream_data = self.receive_buffer.items;
            const consumed_size = switch (self.state) {
                .READ_HEADER => blk: {
                    if (stream_data.len > @sizeOf(protocol.tcp.ConnectHeader)) {
                        // Drop if we received too much data.
                        // Server is not allowed to send more than the actual
                        // connect header.
                        return self.drop(.invalid_data);
                    }
                    if (stream_data.len < @sizeOf(protocol.tcp.ConnectHeader)) {
                        // not yet enough data
                        return;
                    }
                    std.debug.assert(stream_data.len == @sizeOf(protocol.tcp.ConnectHeader));

                    const net_header = @ptrCast(*align(1) const protocol.tcp.ConnectHeader, stream_data.ptr);

                    if (!std.mem.eql(u8, &net_header.magic, &protocol.tcp.magic))
                        return self.drop(.invalid_data);
                    if (net_header.protocol_version != protocol.tcp.protocol_version)
                        return self.drop(.protocol_mismatch);

                    {
                        var header = ConnectionHeader{
                            .password = undefined,
                            .clientName = undefined,
                            .capabilities = @bitCast(u32, net_header.capabilities),
                        };

                        header.password = try std.mem.dupeZ(self.provider.allocator, u8, extractString(&net_header.password));
                        errdefer self.provider.allocator.free(header.password);

                        header.clientName = try std.mem.dupeZ(self.provider.allocator, u8, extractString(&net_header.name));
                        errdefer self.provider.allocator.free(header.clientName);

                        self.header = header;
                    }

                    self.screen_resolution.width = net_header.screen_size_x;
                    self.screen_resolution.height = net_header.screen_size_y;

                    {
                        const lock = self.provider.resource_lock.acquire();
                        defer lock.release();

                        var stream = self.sock.writer();

                        var response = protocol.tcp.ConnectResponse{
                            .success = 1,
                            .resource_count = @intCast(u32, self.provider.resources.count()),
                        };

                        try stream.writeAll(std.mem.asBytes(&response));

                        var iter = self.provider.resources.iterator();
                        while (iter.next()) |kv| {
                            const resource = &kv.value;
                            var descriptor = protocol.tcp.ResourceDescriptor{
                                .id = resource.id,
                                .size = @intCast(u32, resource.data.len),
                                .type = resource.type,
                                .hash = resource.hash,
                            };
                            try stream.writeAll(std.mem.asBytes(&descriptor));
                        }
                    }

                    self.state = .READ_REQUIRED_RESOURCE_HEADER;

                    break :blk @sizeOf(protocol.tcp.ConnectHeader);
                },

                .READ_REQUIRED_RESOURCE_HEADER => blk: {
                    if (stream_data.len < @sizeOf(protocol.tcp.ResourceRequestHeader))
                        return;

                    const header = @ptrCast(*align(1) const protocol.tcp.ResourceRequestHeader, stream_data.ptr);

                    self.required_resource_count = header.request_count;

                    if (self.required_resource_count > 0) {
                        self.required_resources.shrink(0);
                        try self.required_resources.ensureCapacity(self.required_resource_count);

                        self.state = .READ_REQUIRED_RESOURCES;
                    } else {
                        self.state = .READY;

                        // handshake phase is complete,
                        // switch over to main phase
                        self.is_initialized = true;
                    }

                    break :blk @sizeOf(protocol.tcp.ResourceRequestHeader);
                },

                .READ_REQUIRED_RESOURCES => blk: {
                    if (stream_data.len < @sizeOf(protocol.tcp.ResourceRequest))
                        return;

                    const request = @ptrCast(*align(1) const protocol.tcp.ResourceRequest, stream_data.ptr);

                    try self.required_resources.append(request.id);

                    std.debug.assert(self.required_resources.items.len <= self.required_resource_count);
                    if (self.required_resources.items.len == self.required_resource_count) {
                        if (stream_data.len > @sizeOf(protocol.tcp.ResourceRequest)) {
                            // If excess data was sent, we drop the connection
                            return self.drop(.invalid_data);
                        }

                        self.resource_send_index = 0;
                        self.resource_send_offset = 0;
                        self.state = .SEND_RESOURCES;
                    }

                    // wait for a packet of all required resources

                    break :blk @sizeOf(protocol.tcp.ResourceRequest);
                },

                .SEND_RESOURCES => {
                    // we are currently uploading all resources,
                    // receiving anything here would be protocol violation
                    return self.drop(.invalid_data);
                },

                .READY => blk: {
                    if (stream_data.len < 4)
                        return; // Not enough data for size decoding

                    const length = std.mem.readIntLittle(u32, stream_data[0..4]);

                    if (stream_data.len < (4 + length))
                        return; // not enough data

                    try self.decodePacket(stream_data[4..]);

                    break :blk (length + 4);
                },
            };
            std.debug.assert(consumed_size > 0);
            std.debug.assert(consumed_size <= self.receive_buffer.items.len);

            std.mem.copy(u8, self.receive_buffer.items[0..], self.receive_buffer.items[consumed_size..]);

            self.receive_buffer.shrink(self.receive_buffer.items.len - consumed_size);
        }
    }

    //! Is called whenever the socket is ready to send
    //! data and we're not yet in "READY" state
    fn sendData(self: *Self) !void {
        std.debug.assert(self.is_initialized == false);
        std.debug.assert(self.state != .READY);
        switch (self.state) {
            .SEND_RESOURCES => {
                const lock = self.provider.resource_lock.acquire();
                defer lock.release();

                const resource_id = self.required_resources.items[self.resource_send_index];
                const resource = &(self.provider.resources.getEntry(resource_id) orelse return error.ResourceNotFound).value;

                var stream = self.sock.writer();

                if (self.resource_send_offset == 0) {
                    const header = protocol.tcp.ResourceHeader{
                        .id = resource_id,
                        .size = @intCast(u32, resource.data.len),
                    };

                    try stream.writeAll(std.mem.asBytes(&header));
                }

                const rest = resource.data.len - self.resource_send_offset;

                const len = try stream.write(resource.data[self.resource_send_offset .. self.resource_send_offset + rest]);

                self.resource_send_offset += len;
                std.debug.assert(self.resource_send_offset <= resource.data.len);
                if (self.resource_send_offset == resource.data.len) {
                    // sending was completed
                    self.resource_send_index += 1;
                    self.resource_send_offset = 0;
                    if (self.resource_send_index == self.required_resources.items.len) {
                        // sending is done!
                        self.state = .READY;

                        // handshake phase is complete,
                        // switch over to
                        self.is_initialized = true;
                    }
                }
            },
            // we don't need to send anything by-default
            else => return,
        }
    }

    //! transmit a CommandBuffer synchronously
    //! @remarks self will lock the Connection internally,
    //!          so don't wrap self call into a mutex!
    fn send(self: *Self, packet: []const u8) DunstblickError!void {
        std.debug.assert(self.state == .READY);

        if (packet.len > std.math.maxInt(u32))
            return error.OutOfRange;

        errdefer self.drop(.network_error);

        const length = @truncate(u32, packet.len);

        const lock = self.mutex.acquire();
        defer lock.release();

        var stream = self.sock.writer();
        stream.writeIntLittle(u32, length) catch |err| return mapNetworkError(err);
        stream.writeAll(packet[0..length]) catch |err| return mapNetworkError(err);
    }

    fn decodePacket(self: *Self, packet: []const u8) !void {
        var reader = protocol.Decoder.init(packet);

        const msgtype = @intToEnum(protocol.ApplicationCommand, try reader.readByte());

        switch (msgtype) {
            .eventCallback => {
                const id = try reader.readVarUInt();
                const widget = try reader.readVarUInt();

                self.on_event.invoke(.{
                    self,
                    @intToEnum(protocol.EventID, id),
                    @intToEnum(protocol.WidgetName, widget),
                });
            },
            .propertyChanged => {
                const obj_id = try reader.readVarUInt();
                const property = try reader.readVarUInt();
                const value_type = @intToEnum(protocol.Type, try reader.readByte());

                const value = try reader.readValue(value_type, null);

                self.on_property_changed.invoke(.{
                    self,
                    @intToEnum(protocol.ObjectID, obj_id),
                    @intToEnum(protocol.PropertyName, property),
                    &value,
                });
            },
            _ => {
                std.log.err(.dunstblick, "Received {} bytes of an unknown message type {}\n", .{ packet.len, msgtype });
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
            error.OutOfMemory => error.OutOfMemory,
            error.UnknownPacket => error.NetworkError,
            error.EndOfStream => error.EndOfStream,
            error.NotSupported => error.NetworkError,
            else => |e| mapNetworkError(e),
        };
    }

    // User API
    pub fn close(self: *Self, actual_reason: []const u8) void {
        {
            const lock = self.mutex.acquire();
            defer lock.release();

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

    pub fn setView(self: *Self, id: ResourceID) DunstblickError!void {
        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .setView);

        try buffer.writeID(@enumToInt(id));
        try self.send(stream.getWritten());
    }

    pub fn setRoot(self: *Self, id: ObjectID) DunstblickError!void {
        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .setRoot);

        try buffer.writeID(@enumToInt(id));
        try self.send(stream.getWritten());
    }

    pub fn beginChangeObject(self: *Self, id: ObjectID) !*Object {
        var object = try self.provider.allocator.create(Object);
        errdefer self.provider.allocator.destroy(object);

        object.* = try Object.init(self);
        errdefer object.deinit();

        var enc = protocol.makeEncoder(object.commandbuffer.writer());

        try enc.writeID(@enumToInt(id));

        return object;
    }

    pub fn removeObject(self: *Self, id: ObjectID) DunstblickError!void {
        var backing_buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .setRoot);

        try buffer.writeID(@enumToInt(id));
        try self.send(stream.getWritten());
    }

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

    pub fn setProperty(self: *Self, object: ObjectID, name: PropertyName, value: Value) DunstblickError!void {
        var backing_buf: [4096]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .setProperty);

        try buffer.writeID(@enumToInt(object));
        try buffer.writeID(@enumToInt(name));
        try buffer.writeValue(value, true);

        try self.send(stream.getWritten());
    }

    pub fn clear(self: *Self, object: ObjectID, name: PropertyName) DunstblickError!void {
        var backing_buf: [128]u8 = undefined;
        var stream = std.io.fixedBufferStream(&backing_buf);

        var buffer = try protocol.beginDisplayCommandEncoding(stream.writer(), .clear);

        try buffer.writeID(@enumToInt(object));
        try buffer.writeID(@enumToInt(name));

        try self.send(stream.getWritten());
    }

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
};

pub const Application = struct {
    const Self = @This();

    const ResourceMap = std.AutoHashMap(protocol.ResourceID, StoredResource);

    const ConnectionList = std.TailQueue(Connection);
    const ConnectionNode = ConnectionList.Node;

    mutex: std.Mutex,
    allocator: *std.mem.Allocator,

    multicast_sock: xnet.Socket,
    tcp_sock: xnet.Socket,
    discovery_name: []const u8, // owned

    tcp_listener_ep: xnet.EndPoint,

    resource_lock: std.Mutex,

    resources: ResourceMap,

    pending_connections: ConnectionList,
    established_connections: ConnectionList,

    on_connected: struct {
        function: ?ConnectedCallback,
        user_data: ?*c_void,

        fn invoke(self: @This(), args: anytype) void {
            if (self.function) |function| {
                @call(.{}, function, args ++ .{self.user_data});
            } else {
                std.log.debug(.dunstblick, "callback does not exist!\n", .{});
            }
        }
    },

    on_disconnected: struct {
        function: ?DisconnectedCallback,
        user_data: ?*c_void,

        fn invoke(self: @This(), args: anytype) void {
            if (self.function) |function| {
                @call(.{}, function, args ++ .{self.user_data});
            } else {
                std.log.debug(.dunstblick, "callback does not exist!\n", .{});
            }
        }
    },

    socket_set: xnet.SocketSet,

    pub fn open(allocator: *std.mem.Allocator, discoveryName: []const u8) !Self {
        var provider = Self{
            .mutex = std.Mutex.init(),
            .resource_lock = std.Mutex.init(),
            .allocator = allocator,

            .resources = ResourceMap.init(allocator),

            .pending_connections = ConnectionList.init(),
            .established_connections = ConnectionList.init(),

            .on_connected = .{ .function = null, .user_data = null },
            .on_disconnected = .{ .function = null, .user_data = null },

            .socket_set = try xnet.SocketSet.init(allocator),

            // will be initialized in sequence:
            .discovery_name = undefined,
            .tcp_sock = undefined,
            .multicast_sock = undefined,
            .tcp_listener_ep = undefined,
        };
        errdefer provider.resources.deinit();

        provider.discovery_name = try std.mem.dupe(allocator, u8, discoveryName);

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

        std.log.debug(.dunstblick, "provider ready at {}\n", .{try provider.tcp_sock.getLocalEndPoint()});

        return provider;
    }

    pub fn close(self: *Self) void {
        {
            var iter = self.established_connections.first;
            while (iter) |item| {
                var next = item.next;
                defer iter = next;

                self.on_disconnected.invoke(.{
                    self,
                    &item.data,
                    .shutdown,
                });
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

        self.resources.deinit();
        self.tcp_sock.close();
        self.multicast_sock.close();
        self.allocator.free(self.discovery_name);
        self.socket_set.deinit();
    }

    /// timeout is in nanoseconds.
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

        const result = xnet.waitForSocketEvent(&self.socket_set, timeout);

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
        {
            var iter = self.pending_connections.first;
            while (iter) |item| : (iter = item.next) {
                if (item.data.disconnect_reason != null)
                    continue;

                if (self.socket_set.isReadyWrite(item.data.sock)) {
                    item.data.sendData() catch item.data.drop(.invalid_data);
                }
            }
        }

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
                    std.log.err(.dunstblick, "udp message too small…\n", .{});
                } else {
                    if (std.mem.eql(u8, &message.header.magic, &protocol.udp.magic)) {
                        switch (message.header.type) {
                            .discover => {
                                if (msg.numberOfBytes >= @sizeOf(protocol.udp.Discover)) {
                                    var response = protocol.udp.DiscoverResponse{
                                        .header = undefined,
                                        .tcp_port = self.tcp_listener_ep.port,
                                        .length = undefined,
                                        .name = undefined,
                                    };
                                    response.header = protocol.udp.Header.create(.respond_discover);

                                    response.length = @intCast(u16, std.math.min(response.name.len, self.discovery_name.len));

                                    std.mem.set(u8, &response.name, 0);
                                    std.mem.copy(u8, &response.name, self.discovery_name[0..response.length]);

                                    std.log.debug(.dunstblick, "response to {}\n", .{msg.sender});

                                    if (self.multicast_sock.sendTo(msg.sender, std.mem.asBytes(&response))) |sendlen| {
                                        if (sendlen < @sizeOf(protocol.udp.DiscoverResponse)) {
                                            std.log.err(.dunstblick, "expected to send {} bytes, got {}\n", .{
                                                @sizeOf(protocol.udp.DiscoverResponse),
                                                sendlen,
                                            });
                                        }
                                    } else |err| {
                                        std.log.err(.dunstblick, "failed to send udp response: {}\n", .{err});
                                    }
                                } else {
                                    std.log.err(.dunstblick, "expected {} bytes, got {}\n", .{ @sizeOf(protocol.udp.Discover), msg.numberOfBytes });
                                }
                            },
                            .respond_discover => {
                                if (msg.numberOfBytes >= @sizeOf(protocol.udp.DiscoverResponse)) {
                                    std.log.debug(.dunstblick, "got udp response\n", .{});
                                } else {
                                    std.log.err(.dunstblick, "expected {} bytes, got {}\n", .{
                                        @sizeOf(protocol.udp.DiscoverResponse),
                                        msg.numberOfBytes,
                                    });
                                }
                            },

                            _ => |val| {
                                std.log.err(.dunstblick, "invalid packet type: {}\n", .{val});
                            },
                        }
                    } else {
                        std.log.err(.dunstblick, "Invalid packet magic: {X:0>2}{X:0>2}{X:0>2}{X:0>2}\n", .{
                            message.header.magic[0],
                            message.header.magic[1],
                            message.header.magic[2],
                            message.header.magic[3],
                        });
                    }
                }
            } else |err| {
                std.log.err(.dunstblick, "failed to receive udp message: {}\n", .{err});
            }
        }
        if (self.socket_set.isReadyRead(self.tcp_sock)) {
            const socket = self.tcp_sock.accept() catch |err| return mapNetworkError(err);
            errdefer socket.close();

            const ep = socket.getRemoteEndPoint() catch |err| return mapNetworkError(err);

            const node = try self.allocator.create(ConnectionNode);
            errdefer self.allocator.destroy(node);

            node.* = ConnectionNode.init(Connection.init(self, socket, ep));
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

                if (item.data.is_initialized) {
                    self.pending_connections.remove(item);

                    self.on_connected.invoke(.{
                        self,
                        &item.data,
                        item.data.header.?.clientName,
                        item.data.header.?.password,
                        item.data.screen_resolution,
                        item.data.header.?.capabilities,
                    });

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
                    self.established_connections.remove(item);
                    item.data.deinit();
                    self.allocator.destroy(item);
                }
            }
        }
    }

    // Public API

    pub fn addResource(self: *Self, id: protocol.ResourceID, kind: protocol.ResourceKind, data: []const u8) DunstblickError!void {
        const lock = self.mutex.acquire();
        defer lock.release();

        var cloned_data = try std.mem.dupe(self.allocator, u8, data);
        errdefer self.allocator.free(cloned_data);

        const result = try self.resources.getOrPut(id);

        std.debug.assert(result.entry.key == id);
        if (result.found_existing) {
            std.debug.assert(result.entry.value.id == id);
            self.allocator.free(result.entry.value.data);
        } else {
            result.entry.value.id = id;
        }
        result.entry.value.type = @intToEnum(protocol.ResourceKind, @enumToInt(kind));
        result.entry.value.data = cloned_data;
        result.entry.value.updateHash();
    }

    pub fn removeResource(self: *Self, id: protocol.ResourceID) DunstblickError!void {
        const lock = self.mutex.acquire();
        defer lock.release();

        if (self.resources.remove(id)) |item| {
            self.allocator.free(item.value.data);
        }
    }
};

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

    pub fn setProperty(self: *Self, name: protocol.PropertyName, value: Value) DunstblickError!void {
        var enc = protocol.makeEncoder(self.commandbuffer.writer());

        try enc.writeEnum(@intCast(u8, @enumToInt(value.type)));
        try enc.writeID(@enumToInt(name));
        try enc.writeValue(value, false);
    }

    pub fn commit(self: *Self) DunstblickError!void {
        defer self.cancel(); // self will free the memory

        var enc = protocol.makeEncoder(self.commandbuffer.writer());
        try enc.writeEnum(0);

        try self.connection.send(self.commandbuffer.items);
    }

    pub fn cancel(self: *Self) void {
        self.commandbuffer.deinit();
        self.connection.provider.allocator.destroy(self);
    }
};
const std = @import("std");

const xnet = @import("xnet.zig");

const c = @cImport({
    @cInclude("dunstblick.h");
    @cInclude("picohash.h");
});

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

const LogLevel = enum {
    none = 0,
    @"error" = 1,
    diagnostic = 2,
};

const DunstblickError = error{ OutOfMemory, NetworkError, OutOfRange };

fn mapDunstblickError(err: DunstblickError) NativeErrorCode {
    return switch (err) {
        error.OutOfMemory => .DUNSTBLICK_ERROR_OUT_OF_MEMORY,
        error.NetworkError => .DUNSTBLICK_ERROR_NETWORK,
        error.OutOfRange => .DUNSTBLICK_ERROR_ARGUMENT_OUT_OF_RANGE,
    };
}

fn mapDunstblickErrorVoid(value: DunstblickError!void) NativeErrorCode {
    value catch |err| return mapDunstblickError(err);
    return .DUNSTBLICK_ERROR_NONE;
}

const log_level = LogLevel.@"error";

fn log_msg(level: LogLevel, comptime fmt: []const u8, args: var) void {
    if (@enumToInt(level) > @enumToInt(log_level))
        return;
    std.debug.warn(fmt, args);
}

const NetworkCommand = enum(u8) {
    disconnect = 0, // (reason)
    uploadResource = 1, // (rid, kind, data)
    addOrUpdateObject = 2, // (obj)
    removeObject = 3, // (oid)
    setView = 4, // (rid)
    setRoot = 5, // (oid)
    setProperty = 6, // (oid, name, value) // "unsafe command", uses the serverside object type or fails of property
    // does not exist
    clear = 7, // (oid, name)
    insertRange = 8, // (oid, name, index, count, value …) // manipulate lists
    removeRange = 9, // (oid, name, index, count) // manipulate lists
    moveRange = 10, // (oid, name, indexFrom, indexTo, count) // manipulate lists
};

const CommandBuffer = struct {
    const Self = @This();

    buffer: std.ArrayList(u8),

    fn init(command: NetworkCommand, allocator: *std.mem.Allocator) !Self {
        var buffer = Self{
            .buffer = std.ArrayList(u8).init(allocator),
        };
        errdefer buffer.buffer.deinit();
        try buffer.writeByte(@enumToInt(command));
        return buffer;
    }

    fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    fn writeByte(self: *Self, byte: u8) !void {
        try self.buffer.append(byte);
    }

    fn writeEnum(self: *Self, e: u8) !void {
        try self.writeByte(e);
    }

    fn writeID(self: *Self, id: u32) !void {
        // TODO: Implement
        unreachable;
    }

    fn writeString(self: *Self, string: []const u8) !void {
        unreachable;
    }

    fn writeValue(self: *Self, value: Value, prefixType: bool) !void {
        unreachable;
    }

    fn writeVarUInt(self: *Self, value: u32) !void {
        unreachable;
    }

    fn writeVarSInt(self: *Self, value: i32) !void {
        unreachable;
    }
};

fn Callback(comptime F: type) type {
    return struct {
        const Self = @This();
        function: ?F,
        user_data: ?*c_void,

        fn invoke(self: Self, args: var) void {
            if (self.function) |function| {
                @call(.{}, function, args ++ .{self.user_data});
            } else {
                log_msg(.diagnostic, "callback does not exist!\n", .{});
            }
        }
    };
}

const ConnectionHeader = struct {
    clientName: [:0]const u8,
    password: [:0]const u8,
    capabilities: ClientCapabilities,
};

const Md5Hash = [16]u8;

fn computeHash(data: []const u8) Md5Hash {
    var hash: Md5Hash = undefined;

    var ctx: c._picohash_md5_ctx_t = undefined;
    c._picohash_md5_init(&ctx);
    c._picohash_md5_update(&ctx, data.ptr, data.len);
    c._picohash_md5_final(&ctx, &hash);

    return hash;
}

const StoredResource = struct {
    const Self = @This();

    id: ResourceID,
    type: ResourceKind,
    data: []u8, // allocated with dunstblick_Provider.allocator
    hash: Md5Hash,

    fn updateHash(self: *Self) void {
        self.hash = computeHash(self.data);
    }
};

pub const dunstblick_Connection = struct {
    const Self = @This();

    const State = enum {
        READ_HEADER,
        READ_REQUIRED_RESOURCE_HEADER,
        READ_REQUIRED_RESOURCES,
        SEND_RESOURCES,
        READY,
    };

    mutex: std.Mutex,

    sock: xnet.Socket,
    remote: xnet.EndPoint,

    state: State = .READ_HEADER,

    is_initialized: bool = false,
    disconnect_reason: ?DisconnectReason = null,

    header: ConnectionHeader,
    screenResolution: Size,

    receive_buffer: std.ArrayList(u8),
    provider: *dunstblick_Provider,

    ///< total number of resources required by the display client
    required_resource_count: usize,
    ///< ids of the required resources
    required_resources: []ResourceID,
    ///< currently transmitted resource
    resource_send_index: usize,
    ///< current byte offset in the resource
    resource_send_offset: usize,

    user_data_pointer: ?*c_void,

    /// Stores packets received in message pumping
    incoming_packets: std.atomic.Queue([]const u8),

    onEvent: Callback(EventCallback),
    onPropertyChanged: Callback(PropertyChangedCallback),

    fn init(provider: *dunstblick_Provider, sock: xnet.Socket, ep: xnet.EndPoint) dunstblick_Connection {
        log_msg(LOG_DIAGNOSTIC, "connection from %s\n", to_string(remote).c_str());
        return dunstblick_Connection{
            .mutex = std.Mutex.init(),
            .sock = sock,
            .endpoint = endpoint,
            .provider = provider,
            .header = undefined,
            .screenResolution = undefined,
            .receive_buffer = std.ArrayList(u8).init(provider.allocator),
            .required_resource_count = undefined,
            .required_resources = undefined,
            .resource_send_index = undefined,
            .resource_send_offset = undefined,
            .user_data_pointer = null,
            .incoming_packets = std.atomic.Queue(Packet).init(),
            .onEvent = .{ .function = null, .user_data = null },
            .onPropertyChanged = .{ .function = null, .user_data = null },
        };
    }

    fn deinit(self: *Self) void {
        log_msg(.diagnostic, "connection lost to {}\n", .{self.remote});
        self.receive_buffer.deinit();

        while (self.incoming_packets.get()) |packet| {
            self.provider.allocator.free(packet.data);
            self.provider.allocator.destroy(packet);
        }

        self.sock.close();

        self.provider.allocator.free(self.header.password);
        self.provider.allocator.free(self.header.clientName);

        switch (self.state) {
            .READ_REQUIRED_RESOURCES, .SEND_RESOURCES, .READY => {
                self.provider.allocator.free(self.required_resources);
            },
            else => {},
        }
    }

    fn drop(self: *Self, reason: DisconnectReason) void {
        if (self.disconnect_reason)
            return; // already dropped
        self.disconnect_reason = reason;
        log_msg(.diagnostic, "dropped connection to {}: {}\n", .{ self.remote, reason });
    }

    //! Shoves data from the display server into the connection.
    fn pushData(self: *Self, blob: []const u8) !void {
        const MAX_BUFFER_LIMIT = 5 * 1024 * 1024; // 5 MeBiByte

        if (self.receive_buffer.items.len + blob.len >= max_buffer_limit) {
            return self.drop(.DUNSTBLICK_DISCONNECT_INVALID_DATA);
        }

        try self.receive_buffer.appendSlice(blob);

        log_msg(.diagnostic, "read {} bytes from {} into buffer of {}\n", .{
            blob.len,
            self.remote,
            receive_buffer.len,
        });

        while (self.receive_buffer.items.len > 0) {
            const stream_data = self.receive_buffer.items;
            const consumed_size = switch (state) {
                .READ_HEADER => blk: {
                    if (stream_data.len > @sizeOf(TcpConnectHeader)) {
                        // Drop if we received too much data.
                        // Server is not allowed to send more than the actual
                        // connect header.
                        return self.drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
                    }
                    if (stream_data.len < @sizeOf(TcpConnectHeader)) {
                        // not yet enough data
                        return;
                    }
                    assert(stream_data.len == @sizeOf(TcpConnectHeader));

                    const net_header = @ptrCast(*align(1) const TcpConnectHeader, stream_data.data);

                    if (net_header.magic != TcpConnectHeader.real_magic)
                        return drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
                    if (net_header.protocol_version != TcpConnectHeader.current_protocol_version)
                        return drop(DUNSTBLICK_DISCONNECT_PROTOCOL_MISMATCH);

                    self.header.password = try std.mem.dupe(self.provider.allocator, u8, extract_string(net_header.password));
                    self.header.clientName = try std.mem.dupe(self.provider.allocator, u8, extract_string(net_header.name));
                    self.header.capabilities = @intToEnum(ClientCapabilities, net_header.capabilities);

                    self.screenResolution.w = net_header.screenSizeX;
                    self.screenResolution.h = net_header.screenSizeY;

                    {
                        const lock = self.provider.resource_lock.acquire();
                        defer lock.release();

                        var stream = self.sock.outStream();

                        var response = TcpConnectResponse{
                            .success = 1,
                            .resourceCount = provider.resources.count(),
                        };

                        stream.writeAll(std.mem.asBytes(&response));

                        var iter = provider.resources.iterator();
                        while (iter.next()) |kv| {
                            const resource = &kv.value;
                            var descriptor = TcpResourceDescriptor{
                                .id = resource.id,
                                .size = resource.data.len,
                                .type = resource.type,
                                .md5sum = resource.hash,
                            };
                            stream.writeAll(std.mem.asBytes(&descriptor));
                        }
                    }

                    state = .READ_REQUIRED_RESOURCE_HEADER;

                    break :blk @sizeOf(TcpConnectHeader);
                },

                // . READ_REQUIRED_RESOURCE_HEADER=>  {

                //     if (stream_data.len < @sizeOf(TcpResourceRequestHeader))
                //         return;

                //     auto const & header = *reinterpret_cast<TcpResourceRequestHeader const *>(receive_buffer.data());

                //     required_resource_count = header.request_count;

                //     if (required_resource_count > 0) {

                //         self.required_resources.clear();
                //         state = READ_REQUIRED_RESOURCES;
                //     } else {
                //         state = READY;

                //         // handshake phase is complete,
                //         // switch over to main phase
                //         is_initialized = true;
                //     }

                //     consumed_size = @sizeOf(TcpResourceRequestHeader);

                //     break;
                // }

                // . READ_REQUIRED_RESOURCES=>  {
                //     if (stream_data.len < @sizeOf(TcpResourceRequest))
                //         return;

                //     auto const & request = *reinterpret_cast<TcpResourceRequest const *>(receive_buffer.data());

                //     self.required_resources.emplace_back(request.id);

                //     assert(required_resources.size() <= required_resource_count);
                //     if (required_resources.size() == required_resource_count) {

                //         if (stream_data.len > @sizeOf(TcpResourceRequest)) {
                //             // If excess data was sent, we drop the connection
                //             return drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
                //         }

                //         resource_send_index = 0;
                //         resource_send_offset = 0;
                //         state = SEND_RESOURCES;
                //     }

                //     // wait for a packet of all required resources

                //     consumed_size = @sizeOf(TcpResourceRequest);
                //     break;
                // }

                // . SEND_RESOURCES=> {
                //     // we are currently uploading all resources,
                //     // receiving anything here would be protocol violation
                //     return drop(DUNSTBLICK_DISCONNECT_INVALID_DATA);
                // }

                // . READY => {
                //     if (stream_data.len < 4)
                //         return; // Not enough data for size decoding

                //     uint32_t const length = *reinterpret_cast<uint32_t const *>(receive_buffer.data());

                //     if (stream_data.len < (4 + length))
                //         return; // not enough data

                //     Packet packet(length);
                //     memcpy(packet.data(), receive_buffer.data() + 4, length);

                //     self.incoming_packets.enqueue(std::move(packet));

                //     consumed_size = length + 4;
                //     break;
                // }
            };
            std.debug.assert(consumed_size > 0);
            std.debug.assert(consumed_size <= self.receive_buffer.items.len);

            std.mem.copy(u8, self.receive_buffer.items[0..], self.receive_buffer.items[consumed_size..]);

            self.receive_buffer.shrink(self.receive_buffer.items.len - consumed_size);
        }
    }

    //! Is called whenever the socket is ready to send
    //! data and we're not yet in "READY" state
    fn send_data(self: *self) !void {
        std.debug.assert(self.is_initialized == false);
        std.debug.assert(self.state != .READY);
        switch (self.state) {
            .SEND_RESOURCES => {
                self.provider.resource_lock.lock();
                defer self.provider.resource_lock.unlock();

                const resource_id = self.required_resources[self.resource_send_index];
                const resource = self.provider.resources.get(resource_id);

                if (self.resource_send_offset == 0) {
                    const header = TcpResourceHeader{
                        .id = resource_id,
                        .size = resource.data.len,
                    };

                    try self.sock.outStream().write(header);
                }

                const rest = resource.data.len - self.resource_send_offset;

                const len = try self.sock.write(resource.data[resource_send_offset .. resource_send_offset + rest]);

                self.resource_send_offset += len;
                std.debug.assert(self.resource_send_offset <= resource.data.len);
                if (self.resource_send_offset == resource.data.len) {
                    // sending was completed
                    self.resource_send_index += 1;
                    self.resource_send_offset = 0;
                    if (self.resource_send_index == self.required_resources.len) {
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
    fn send(self: *Self, packet: CommandBuffer) DunstblickError!void {
        std.debug.assert(self.state == .READY);

        if (packet.buffer.len > std.math.maxInt(u32))
            return error.OutOfRange;

        const length = @truncate(u32, packet.buffer.len);

        const lock = self.mutex.acquire();
        defer lock.release();

        var stream = self.sock.outStream();
        try stream.writeIntLittle(u32, length);
        try stream.writeAll(packet.buffer.items[0..length]);
    }

    // User API
    pub fn setView(self: *Self, id: ResourceID) !void {
        var buffer = try CommandBuffer.init(.setView, self.provider.allocator);
        defer buffer.deinit();

        try buffer.writeID(id);
        try self.send(buffer);
    }

    pub fn setRoot(self: *Self, id: ObjectID) !void {
        var buffer = try CommandBuffer.init(.setRoot, self.provider.allocator);
        defer buffer.deinit();

        try buffer.writeID(id);
        try self.send(buffer);
    }

    pub fn beginChangeObject(self: *Self, id: ObjectID) !*dunstblick_Object {
        var object = try self.provider.allocator.create(dunstblick_Object);
        errdefer self.provider.allocator.destroy(object);

        object.* = try dunstblick_Object.init(self);
        errdefer object.deinit();

        try object.commandbuffer.writeID(id);

        return object;
    }

    pub fn removeObject(self: *Self, id: ObjectID) !void {
        var buffer = try CommandBuffer.init(.setRoot, self.provider.allocator);
        defer buffer.deinit();

        try buffer.writeID(id);
        try self.send(buffer);
    }

    pub fn moveRange(self: *Self, object: ObjectID, name: PropertyName, indexFrom: u32, indexTo: u32, count: u32) !void {
        var buffer = try CommandBuffer.init(.moveRange, self.provider.allocator);
        defer buffer.deinit();

        try buffer.writeID(object);
        try buffer.writeID(name);
        try buffer.writeVarUInt(indexFrom);
        try buffer.writeVarUInt(indexTo);
        try buffer.writeVarUInt(count);

        try self.send(buffer);
    }

    pub fn setProperty(self: *Self, object: ObjectID, name: PropertyName, value: Value) !void {
        var buffer = try CommandBuffer.init(.setProperty, self.provider.allocator);
        defer buffer.deinit();

        try buffer.writeID(object);
        try buffer.writeID(name);
        try buffer.writeValue(value, true);

        try self.send(buffer);
    }

    pub fn clear(self: *Self, object: ObjectID, name: PropertyName) !void {
        var buffer = try CommandBuffer.init(.clear, self.provider.allocator);
        defer buffer.deinit();

        try buffer.writeID(object);
        try buffer.writeID(name);

        try self.send(buffer);
    }

    pub fn insertRange(self: *Self, object: ObjectID, name: PropertyName, index: u32, values: []const ObjectID) !void {
        var buffer = try CommandBuffer.init(.insertRange, self.provider.allocator);
        defer buffer.deinit();

        try buffer.writeID(object);
        try buffer.writeID(name);
        try buffer.writeVarUInt(index);
        try buffer.writeVarUInt(@intCast(u32, values.len));

        for (values) |id| {
            try buffer.writeID(id);
        }

        try self.send(buffer);
    }

    pub fn removeRange(self: *Self, object: ObjectID, name: PropertyName, index: u32, count: u32) !void {
        var buffer = try CommandBuffer.init(.removeRange, self.provider.allocator);
        defer buffer.deinit();

        try buffer.writeID(object);
        try buffer.writeID(name);
        try buffer.writeVarUInt(index);
        try buffer.writeVarUInt(count);

        try self.send(buffer);
    }
};

pub const dunstblick_Provider = struct {
    const Self = @This();

    const ResourceMap = std.AutoHashMap(ResourceID, StoredResource);

    mutex: std.Mutex,
    allocator: *std.mem.Allocator,

    multicast_sock: xnet.Socket,
    tcp_sock: xnet.Socket,
    discovery_name: []const u8, // owned

    tcp_listener_ep: xnet.EndPoint,

    resource_lock: std.Mutex,

    resources: ResourceMap,

    const ConnectionList = std.TailQueue(dunstblick_Connection);
    const ConnectionNode = ConnectionList.Node;

    pending_connections: ConnectionList,
    established_connections: ConnectionList,

    onConnected: Callback(ConnectedCallback),
    onDisconnected: Callback(DisconnectedCallback),

    pub fn init(allocator: *std.mem.Allocator, discoveryName: []const u8) !Self {
        var provider = Self{
            .mutex = std.Mutex.init(),
            .resource_lock = std.Mutex.init(),
            .allocator = allocator,

            .resources = ResourceMap.init(allocator),

            .pending_connections = ConnectionList.init(),
            .established_connections = ConnectionList.init(),

            .onConnected = .{ .function = null, .user_data = null },
            .onDisconnected = .{ .function = null, .user_data = null },

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
        try provider.multicast_sock.bindToPort(DUNSTBLICK_DEFAULT_PORT);

        try provider.multicast_sock.joinMulticastGroup(.{
            .interface = xnet.Address.IPv4.any,
            .group = DUNSTBLICK_MULTICAST_GROUP,
        });

        return provider;
    }

    pub fn close(self: *Self) void {
        {
            var iter = self.established_connections.first;
            while (iter) |item| {
                var next = item.next;
                defer iter = next;

                self.onDisconnected.invoke(.{
                    @ptrCast(*c.struct_dunstblick_Provider, self),
                    @ptrCast(*c.struct_dunstblick_Connection, &item.data),
                    .DUNSTBLICK_DISCONNECT_SHUTDOWN,
                });
                dunstblick_CloseConnection(&item.data, "The provider has been shut down.");
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
    }

    /// timeout is in nanoseconds.
    fn pumpEvents(self: *Self, timeout: ?u64) !void {
        unreachable;
    }

    // Public API

    pub fn addResource(self: *Self, id: ResourceID, kind: ResourceKind, data: []const u8) !void {
        const lock = self.mutex.acquire();
        defer lock.release();

        var cloned_data = try std.mem.dupe(self.allocator, u8, data);
        errdefer self.allocator.free(cloned_data);

        const result = try self.resources.getOrPut(id);

        std.debug.assert(result.kv.key == id);
        if (result.found_existing) {
            std.debug.assert(result.kv.value.id == id);
            self.allocator.free(result.kv.value.data);
        } else {
            result.kv.value.id = id;
        }
        result.kv.value.type = kind;
        result.kv.value.data = cloned_data;
        result.kv.value.updateHash();
    }

    pub fn removeResource(self: *Self, id: ResourceID) !void {
        const lock = self.mutex.acquire();
        defer lock.release();

        if (self.resources.remove(id)) |item| {
            self.allocator.free(item.value.data);
        }
    }
};

const dunstblick_Object = struct {
    const Self = @This();
    connection: *dunstblick_Connection,
    commandbuffer: CommandBuffer,

    fn init(con: *dunstblick_Connection) !Self {
        return Self{
            .connection = con,
            .commandbuffer = try CommandBuffer.init(.addOrUpdateObject, con.provider.allocator),
        };
    }

    fn deinit(self: Self) void {}

    fn setProperty(self: *Self, name: PropertyName, value: Value) !void {
        try self.commandbuffer.writeEnum(@intCast(u8, @enumToInt(value.type)));
        try self.commandbuffer.writeID(name);
        try self.commandbuffer.writeValue(value, false);
    }

    fn commit(self: *Self) !void {
        defer self.cancel(); // self will free the memory

        try self.commandbuffer.writeEnum(0);
        try self.connection.send(self.commandbuffer);
    }

    fn cancel(self: *Self) void {
        self.commandbuffer.deinit();
        self.connection.provider.allocator.destroy(self);
    }
};

// void dunstblick_Provider::pump_events(std::optional<std::chrono::microseconds> timeout)
// {
//     xnet::socket_set read_fds, write_fds;
//     read_fds.add(self.multicast_sock.handle);
//     read_fds.add(self.tcp_sock.handle);

//     for (auto const & connection : self.pending_connections) {
//         read_fds.add(connection.sock);
//         write_fds.add(connection.sock);
//     }
//     for (auto const & connection : self.established_connections) {
//         read_fds.add(connection.sock);
//     }

//     size_t result = select(read_fds, write_fds, xstd::nullopt, timeout);
//     (void)result;

//     std::array<uint8_t, 4096> blob;

//     auto const readAndPushToConnection = [&](dunstblick_Connection & con) . void {
//         if (not read_fds.contains(con.sock))
//             return;

//         ssize_t len = con.sock.read(blob.data(), blob.size());
//         if (len < 0) {
//             con.disconnect_reason = DUNSTBLICK_DISCONNECT_NETWORK_ERROR;
//             perror("failed to read from connection");
//         } else if (len == 0) {
//             con.disconnect_reason = DUNSTBLICK_DISCONNECT_QUIT;
//         } else if (len > 0) {
//             con.push_data(blob.data(), size_t(len));
//         }
//     };

//     // REQUIRED send_data must be called before push_data:
//     // Sending is not allowed to be called on established connections,
//     // but receiving a frame of "i don't require resources" will
//     // switch the connection in READY state without having the need of
//     // ever sending data.

//     // FIRST self
//     for (auto & connection : self.pending_connections) {
//         if (not write_fds.contains(connection.sock))
//             continue;
//         connection.send_data();
//     }

//     // THEN self
//     for (auto & connection : self.pending_connections) {
//         readAndPushToConnection(connection);
//     }
//     for (auto & connection : self.established_connections) {
//         readAndPushToConnection(connection);
//     }

//     if (read_fds.contains(self.multicast_sock)) {
//         fflush(stdout);

//         UdpBaseMessage message;

//         auto const [ssize, sender] = self.multicast_sock.read_from(&message, sizeof message);
//         if (ssize < 0) {
//             perror("read udp failed");
//         } else {
//             size_t size = size_t(ssize);
//             if (size < @sizeOf(message.header)) {
//                 log_msg(LOG_ERROR, "udp message too small…\n");
//             } else {
//                 if (message.header.magic == UdpHeader::real_magic) {
//                     switch (message.header.type) {
//                         case UDP_DISCOVER: {
//                             if (size >= @sizeOf(message.discover)) {
//                                 UdpDiscoverResponse response;
//                                 response.header = UdpHeader::create(UDP_RESPOND_DISCOVER);
//                                 response.tcp_port = uint16_t(tcp_listener_ep.port());
//                                 response.length = self.discovery_name.size();

//                                 strncpy(response.name.data(), self.discovery_name.c_str(), response.name.size());

//                                 log_msg(LOG_DIAGNOSTIC, "response to %s\n", xnet::to_string(sender).c_str());

//                                 ssize_t const sendlen =
//                                     self.multicast_sock.write_to(sender, &response, sizeof response);
//                                 if (sendlen < 0) {
//                                     log_msg(LOG_ERROR, "%s\n", strerror(errno));
//                                 } else if (size_t(sendlen) < @sizeOf(response)) {
//                                     log_msg(LOG_ERROR,
//                                             "expected to send %lu bytes, got %ld\n",
//                                             @sizeOf(response),
//                                             sendlen);
//                                 }
//                             } else {
//                                 log_msg(LOG_ERROR, "expected %lu bytes, got %ld\n", @sizeOf(message.discover), size);
//                             }
//                             break;
//                         }
//                         case UDP_RESPOND_DISCOVER: {
//                             if (size >= @sizeOf(message.discover_response)) {
//                                 log_msg(LOG_DIAGNOSTIC, "got udp response\n");
//                             } else {
//                                 log_msg(LOG_ERROR,
//                                         "expected %lu bytes, got %ld\n",
//                                         @sizeOf(message.discover_response),
//                                         size);
//                             }
//                             break;
//                         }
//                         default:
//                             log_msg(LOG_ERROR, "invalid packet type: %u\n", message.header.type);
//                     }
//                 } else {
//                     log_msg(LOG_ERROR,
//                             "Invalid packet magic: %02X%02X%02X%02X\n",
//                             message.header.magic[0],
//                             message.header.magic[1],
//                             message.header.magic[2],
//                             message.header.magic[3]);
//                 }
//             }
//         }
//     }
//     if (read_fds.contains(self.tcp_sock)) {
//         auto [socket, endpoint] = self.tcp_sock.accept();

//         self.pending_connections.emplace_back(self, std::move(socket), endpoint);
//     }

//     self.pending_connections.remove_if(
//         [&](dunstblick_Connection & con) . bool { return con.disconnect_reason.has_value(); });

//     // Sorts connections from "pending" to "ready"
//     self.pending_connections.sort([](dunstblick_Connection const & a, dunstblick_Connection const & b) . bool {
//         return a.is_initialized < b.is_initialized;
//     });

//     auto it = self.pending_connections.begin();
//     auto end = self.pending_connections.end();
//     while (it != end and not it.is_initialized) {
//         std::advance(it, 1);
//     }
//     if (it != end) {
//         // we found connections that are ready
//         auto const start = it;

//         do {
//             self.onConnected.invoke(self,
//                                      &(*it),
//                                      it.header.clientName.c_str(),
//                                      it.header.password.c_str(),
//                                      it.screenResolution,
//                                      it.header.capabilities);

//             std::advance(it, 1);
//         } while (it != end);

//         // Now transfer all established connections to the other set.
//         self.established_connections.splice(self.established_connections.begin(),
//                                              self.pending_connections,
//                                              start,
//                                              end);
//     }

//     self.established_connections.remove_if([&](dunstblick_Connection & con) . bool {
//         if (not con.disconnect_reason)
//             return false;
//         self.onDisconnected.invoke(self, &con, *con.disconnect_reason);
//         return true;
//     });

//     for (auto & con : self.established_connections) {
//         Packet packet;
//         while (con.incoming_packets.try_dequeue(packet)) {

//             DataReader reader{packet.data(), packet.size()};

//             auto const msgtype = ServerMessageType(reader.read_byte());

//             switch (msgtype) {
//                 case ServerMessageType::eventCallback: {
//                     auto const id = reader.read_uint();
//                     auto const widget = reader.read_uint();

//                     con.onEvent.invoke(&con, id, widget);

//                     break;
//                 }
//                 case ServerMessageType::propertyChanged: {
//                     auto const obj_id = reader.read_uint();
//                     auto const property = reader.read_uint();
//                     auto const type = dunstblick_Type(reader.read_byte());

//                     Value value = reader.read_value(type);

//                     con.onPropertyChanged.invoke(&con, obj_id, property, &value);

//                     break;
//                 }
//                 default:
//                     log_msg(LOG_ERROR,
//                             "Received %lu bytes of an unknown message type %u\n",
//                             packet.size(),
//                             uint32_t(msgtype));
//                     // log some message?
//                     break;
//             }
//         }
//     }
// }

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

    const lock = connection.mutex.acquire();
    defer lock.release();

    if (connection.disconnect_reason != null)
        return;

    connection.disconnect_reason = .DUNSTBLICK_DISCONNECT_SHUTDOWN;

    var buffer = CommandBuffer.init(.disconnect, connection.provider.allocator) catch return;
    defer buffer.deinit();

    buffer.writeString(actual_reason) catch return;

    connection.send(buffer) catch return;
}

export fn dunstblick_GetClientName(connection: *dunstblick_Connection) callconv(.C) [*:0]const u8 {
    return connection.header.clientName;
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

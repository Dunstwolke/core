const std = @import("std");

const xnet = @import("xnet.zig");

// Enforce creation of the library C bindings
comptime {
    _ = @import("c-binding.zig");
}

const c = @import("c.zig");

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

pub const DunstblickError = error{
    OutOfMemory,
    NetworkError,
    OutOfRange,
    EndOfStream,
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
};

fn mapNetworkError(value: NetworkError) DunstblickError {
    log_msg(.diagnostic, "network error: {}:\n", .{value});
    switch (value) {
        else => |e| return error.NetworkError,
    }
}

const log_level = LogLevel.diagnostic;

fn log_msg(level: LogLevel, comptime fmt: []const u8, args: var) void {
    if (@enumToInt(level) > @enumToInt(log_level))
        return;
    std.debug.warn(fmt, args);
}

fn extractString(str: []const u8) []const u8 {
    for (str) |chr, i| {
        if (chr == 0)
            return str[0..i];
    }
    return str;
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
    _,
};

const ServerMessageType = enum(u8) {
    eventCallback = 1, // (cid)
    propertyChanged = 2, // (oid, name, type, value)
    _,
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

    fn writeRaw(self: *Self, data: []const u8) !void {
        try self.buffer.appendSlice(data);
    }

    fn writeEnum(self: *Self, e: u8) !void {
        try self.writeByte(e);
    }

    fn writeID(self: *Self, id: u32) !void {
        try self.writeVarUInt(id);
    }

    fn writeString(self: *Self, string: []const u8) !void {
        try self.writeVarUInt(@intCast(u32, string.len));
        try self.writeRaw(string);
    }

    fn writeNumber(self: *Self, number: f32) !void {
        std.debug.assert(std.builtin.endian == .Little);
        try self.writeRaw(std.mem.asBytes(&number));
    }

    fn writeVarUInt(self: *Self, value: u32) !void {
        var buf: [5]u8 = undefined;

        var maxidx: usize = 4;

        comptime var n: usize = 0;
        inline while (n < 5) : (n += 1) {
            const chr = &buf[4 - n];
            chr.* = @truncate(u8, (value >> (7 * n)) & 0x7F);
            if (chr.* != 0)
                maxidx = 4 - n;
            if (n > 0)
                chr.* |= 0x80;
        }

        std.debug.assert(maxidx < 5);
        try self.writeRaw(buf[maxidx..]);
    }

    fn writeVarSInt(self: *Self, value: i32) !void {
        try self.writeVarUInt(ZigZagInt.encode(value));
    }

    fn writeValue(self: *Self, value: Value, prefixType: bool) !void {
        if (prefixType) {
            try self.writeEnum(@intCast(u8, @enumToInt(value.type)));
        }
        const val = &value.unnamed_3;
        switch (value.type) {
            .DUNSTBLICK_TYPE_INTEGER => try self.writeVarSInt(val.integer),

            .DUNSTBLICK_TYPE_NUMBER => try self.writeNumber(val.number),

            .DUNSTBLICK_TYPE_STRING => try self.writeString(std.mem.span(val.string)),

            .DUNSTBLICK_TYPE_ENUMERATION => try self.writeEnum(val.enumeration),

            .DUNSTBLICK_TYPE_MARGINS => {
                try self.writeVarUInt(val.margins.left);
                try self.writeVarUInt(val.margins.top);
                try self.writeVarUInt(val.margins.right);
                try self.writeVarUInt(val.margins.bottom);
            },

            .DUNSTBLICK_TYPE_COLOR => {
                try self.writeByte(val.color.r);
                try self.writeByte(val.color.g);
                try self.writeByte(val.color.b);
                try self.writeByte(val.color.a);
            },

            .DUNSTBLICK_TYPE_SIZE => {
                try self.writeVarUInt(val.size.w);
                try self.writeVarUInt(val.size.h);
            },

            .DUNSTBLICK_TYPE_POINT => {
                try self.writeVarSInt(val.point.x);
                try self.writeVarSInt(val.point.y);
            },

            .DUNSTBLICK_TYPE_RESOURCE => try self.writeVarUInt(val.resource),

            .DUNSTBLICK_TYPE_BOOLEAN => try self.writeByte(if (val.boolean) 1 else 0),

            .DUNSTBLICK_TYPE_OBJECT => try self.writeVarUInt(val.resource),

            .DUNSTBLICK_TYPE_OBJECTLIST => unreachable, // not implemented yet

            else => unreachable, // api violation
        }
    }
};

const ZigZagInt = struct {
    fn encode(n: i32) u32 {
        const v = (n << 1) ^ (n >> 31);
        return @bitCast(u32, v);
    }
    fn decode(u: u32) i32 {
        const n = @bitCast(i32, u);
        return (n << 1) ^ (n >> 31);
    }
};

test "ZigZag" {
    const input = 42;
    std.debug.assert(ZigZagInt.encode(input) == 84);
    std.debug.assert(ZigZagInt.decode(84) == input);
}

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

    const PacketQueue = std.atomic.Queue([]const u8);

    mutex: std.Mutex,

    sock: xnet.Socket,
    remote: xnet.EndPoint,

    state: State = .READ_HEADER,

    is_initialized: bool = false,
    disconnect_reason: ?DisconnectReason = null,

    header: ?ConnectionHeader,
    screenResolution: Size,

    receive_buffer: std.ArrayList(u8),
    provider: *dunstblick_Provider,

    ///< total number of resources required by the display client
    required_resource_count: usize,
    ///< ids of the required resources
    required_resources: std.ArrayList(ResourceID),
    ///< currently transmitted resource
    resource_send_index: usize,
    ///< current byte offset in the resource
    resource_send_offset: usize,

    user_data_pointer: ?*c_void,

    onEvent: Callback(EventCallback), // Lock access to event in multithreaded scenarios!
    onPropertyChanged: Callback(PropertyChangedCallback), // Lock access to event in multithreaded scenarios!

    fn init(provider: *dunstblick_Provider, sock: xnet.Socket, endpoint: xnet.EndPoint) dunstblick_Connection {
        log_msg(.diagnostic, "connection from {}\n", .{endpoint});
        return dunstblick_Connection{
            .mutex = std.Mutex.init(),
            .sock = sock,
            .remote = endpoint,
            .provider = provider,
            .header = null,
            .screenResolution = undefined,
            .receive_buffer = std.ArrayList(u8).init(provider.allocator),
            .required_resource_count = undefined,
            .required_resources = std.ArrayList(ResourceID).init(provider.allocator),
            .resource_send_index = undefined,
            .resource_send_offset = undefined,
            .user_data_pointer = null,
            .onEvent = .{ .function = null, .user_data = null },
            .onPropertyChanged = .{ .function = null, .user_data = null },
        };
    }

    fn deinit(self: *Self) void {
        log_msg(.diagnostic, "connection lost to {}\n", .{self.remote});
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
        log_msg(.diagnostic, "dropped connection to {}: {}\n", .{ self.remote, reason });
    }

    //! Shoves data from the display server into the connection.
    fn pushData(self: *Self, blob: []const u8) !void {
        const MAX_BUFFER_LIMIT = 5 * 1024 * 1024; // 5 MeBiByte

        if (self.receive_buffer.items.len + blob.len >= MAX_BUFFER_LIMIT) {
            return self.drop(.DUNSTBLICK_DISCONNECT_INVALID_DATA);
        }

        try self.receive_buffer.appendSlice(blob);

        log_msg(.diagnostic, "read {} bytes from {} into buffer of {}\n", .{
            blob.len,
            self.remote,
            self.receive_buffer.items.len,
        });

        while (self.receive_buffer.items.len > 0) {
            const stream_data = self.receive_buffer.items;
            const consumed_size = switch (self.state) {
                .READ_HEADER => blk: {
                    if (stream_data.len > @sizeOf(protocol.TcpConnectHeader)) {
                        // Drop if we received too much data.
                        // Server is not allowed to send more than the actual
                        // connect header.
                        return self.drop(.DUNSTBLICK_DISCONNECT_INVALID_DATA);
                    }
                    if (stream_data.len < @sizeOf(protocol.TcpConnectHeader)) {
                        // not yet enough data
                        return;
                    }
                    std.debug.assert(stream_data.len == @sizeOf(protocol.TcpConnectHeader));

                    const net_header = @ptrCast(*align(1) const protocol.TcpConnectHeader, stream_data.ptr);

                    if (!std.mem.eql(u8, &net_header.magic, &protocol.TcpConnectHeader.real_magic))
                        return self.drop(.DUNSTBLICK_DISCONNECT_INVALID_DATA);
                    if (net_header.protocol_version != protocol.TcpConnectHeader.current_protocol_version)
                        return self.drop(.DUNSTBLICK_DISCONNECT_PROTOCOL_MISMATCH);

                    {
                        var header = ConnectionHeader{
                            .password = undefined,
                            .clientName = undefined,
                            .capabilities = @intToEnum(ClientCapabilities, @intCast(c_int, net_header.capabilities)),
                        };

                        header.password = try std.mem.dupeZ(self.provider.allocator, u8, extractString(&net_header.password));
                        errdefer self.provider.allocator.free(header.password);

                        header.clientName = try std.mem.dupeZ(self.provider.allocator, u8, extractString(&net_header.name));
                        errdefer self.provider.allocator.free(header.clientName);

                        self.header = header;
                    }

                    self.screenResolution.w = net_header.screenSizeX;
                    self.screenResolution.h = net_header.screenSizeY;

                    {
                        const lock = self.provider.resource_lock.acquire();
                        defer lock.release();

                        var stream = self.sock.outStream();

                        var response = protocol.TcpConnectResponse{
                            .success = 1,
                            .resourceCount = @intCast(u32, self.provider.resources.count()),
                        };

                        try stream.writeAll(std.mem.asBytes(&response));

                        var iter = self.provider.resources.iterator();
                        while (iter.next()) |kv| {
                            const resource = &kv.value;
                            var descriptor = protocol.TcpResourceDescriptor{
                                .id = resource.id,
                                .size = @intCast(u32, resource.data.len),
                                .type = resource.type,
                                .md5sum = resource.hash,
                            };
                            try stream.writeAll(std.mem.asBytes(&descriptor));
                        }
                    }

                    self.state = .READ_REQUIRED_RESOURCE_HEADER;

                    break :blk @sizeOf(protocol.TcpConnectHeader);
                },

                .READ_REQUIRED_RESOURCE_HEADER => blk: {
                    if (stream_data.len < @sizeOf(protocol.TcpResourceRequestHeader))
                        return;

                    const header = @ptrCast(*align(1) const protocol.TcpResourceRequestHeader, stream_data.ptr);

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

                    break :blk @sizeOf(protocol.TcpResourceRequestHeader);
                },

                .READ_REQUIRED_RESOURCES => blk: {
                    if (stream_data.len < @sizeOf(protocol.TcpResourceRequest))
                        return;

                    const request = @ptrCast(*align(1) const protocol.TcpResourceRequest, stream_data.ptr);

                    try self.required_resources.append(request.id);

                    std.debug.assert(self.required_resources.items.len <= self.required_resource_count);
                    if (self.required_resources.items.len == self.required_resource_count) {
                        if (stream_data.len > @sizeOf(protocol.TcpResourceRequest)) {
                            // If excess data was sent, we drop the connection
                            return self.drop(.DUNSTBLICK_DISCONNECT_INVALID_DATA);
                        }

                        self.resource_send_index = 0;
                        self.resource_send_offset = 0;
                        self.state = .SEND_RESOURCES;
                    }

                    // wait for a packet of all required resources

                    break :blk @sizeOf(protocol.TcpResourceRequest);
                },

                .SEND_RESOURCES => {
                    // we are currently uploading all resources,
                    // receiving anything here would be protocol violation
                    return self.drop(.DUNSTBLICK_DISCONNECT_INVALID_DATA);
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
                const resource = &(self.provider.resources.get(resource_id) orelse return error.ResourceNotFound).value;

                var stream = self.sock.outStream();

                if (self.resource_send_offset == 0) {
                    const header = protocol.TcpResourceHeader{
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
    fn send(self: *Self, packet: CommandBuffer) DunstblickError!void {
        std.debug.assert(self.state == .READY);

        if (packet.buffer.items.len > std.math.maxInt(u32))
            return error.OutOfRange;

        errdefer self.drop(.DUNSTBLICK_DISCONNECT_NETWORK_ERROR);

        const length = @truncate(u32, packet.buffer.items.len);

        const lock = self.mutex.acquire();
        defer lock.release();

        var stream = self.sock.outStream();
        stream.writeIntLittle(u32, length) catch |err| return mapNetworkError(err);
        stream.writeAll(packet.buffer.items[0..length]) catch |err| return mapNetworkError(err);
    }

    fn decodePacket(self: *Self, packet: []const u8) !void {
        var reader = DataReader.init(packet);

        const msgtype = @intToEnum(ServerMessageType, try reader.readByte());

        switch (msgtype) {
            .eventCallback => {
                const id = try reader.readVarUInt();
                const widget = try reader.readVarUInt();

                self.onEvent.invoke(.{
                    @ptrCast(*c.dunstblick_Connection, self),
                    id,
                    widget,
                });
            },
            .propertyChanged => {
                const obj_id = try reader.readVarUInt();
                const property = try reader.readVarUInt();
                const _type = @intToEnum(c.dunstblick_Type, try reader.readByte());

                const value = try reader.readValue(_type);

                self.onPropertyChanged.invoke(.{
                    @ptrCast(*c.dunstblick_Connection, self),
                    obj_id,
                    property,
                    &value,
                });
            },
            _ => {
                log_msg(.@"error", "Received {} bytes of an unknown message type {}\n", .{ packet.len, msgtype });
                return error.UnknownPacket;
            },
        }
    }

    fn receiveData(self: *Self) DunstblickError!void {
        var buffer: [4096]u8 = undefined;
        const len = self.sock.receive(&buffer) catch |err| return mapNetworkError(err);
        if (len == 0)
            return self.drop(.DUNSTBLICK_DISCONNECT_QUIT);

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

            self.disconnect_reason = .DUNSTBLICK_DISCONNECT_SHUTDOWN;
        }

        var buffer = CommandBuffer.init(.disconnect, self.provider.allocator) catch return;
        defer buffer.deinit();

        buffer.writeString(actual_reason) catch return;

        self.send(buffer) catch return;
    }

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

    socket_set: xnet.SocketSet,

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

            .socket_set = xnet.SocketSet.init(allocator),

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

        log_msg(.diagnostic, "provider ready at {}\n", .{try provider.tcp_sock.getLocalEndPoint()});

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
    pub fn pumpEvents(self: *Self, timeout: ?u64) !void {
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
                    item.data.drop(.DUNSTBLICK_DISCONNECT_NETWORK_ERROR);
            }
        }
        {
            var iter = self.established_connections.first;
            while (iter) |item| : (iter = item.next) {
                if (self.socket_set.isFaulted(item.data.sock))
                    item.data.drop(.DUNSTBLICK_DISCONNECT_NETWORK_ERROR);
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
                    item.data.sendData() catch item.data.drop(.DUNSTBLICK_DISCONNECT_INVALID_DATA);
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
            var message: UdpBaseMessage = undefined;

            if (self.multicast_sock.receiveFrom(std.mem.asBytes(&message))) |msg| {
                if (msg.numberOfBytes < @sizeOf(UdpHeader)) {
                    log_msg(.@"error", "udp message too small…\n", .{});
                } else {
                    if (std.mem.eql(u8, &message.header.magic, &UdpHeader.real_magic)) {
                        switch (@intToEnum(UdpAnnouncementType, message.header.type)) {
                            .UDP_DISCOVER => {
                                if (msg.numberOfBytes >= @sizeOf(UdpDiscover)) {
                                    var response = UdpDiscoverResponse{
                                        .header = undefined,
                                        .tcp_port = self.tcp_listener_ep.port,
                                        .length = undefined,
                                        .name = undefined,
                                    };
                                    response.header = UdpHeader.create(UdpAnnouncementType.UDP_RESPOND_DISCOVER);

                                    response.length = @intCast(u16, std.math.min(response.name.len, self.discovery_name.len));

                                    std.mem.set(u8, &response.name, 0);
                                    std.mem.copy(u8, &response.name, self.discovery_name[0..response.length]);

                                    log_msg(.diagnostic, "response to {}\n", .{msg.sender});

                                    if (self.multicast_sock.sendTo(msg.sender, std.mem.asBytes(&response))) |sendlen| {
                                        if (sendlen < @sizeOf(UdpDiscoverResponse)) {
                                            log_msg(.@"error", "expected to send {} bytes, got {}\n", .{
                                                @sizeOf(UdpDiscoverResponse),
                                                sendlen,
                                            });
                                        }
                                    } else |err| {
                                        log_msg(.@"error", "failed to send udp response: {}\n", .{err});
                                    }
                                } else {
                                    log_msg(.@"error", "expected {} bytes, got {}\n", .{ @sizeOf(UdpDiscover), msg.numberOfBytes });
                                }
                            },
                            .UDP_RESPOND_DISCOVER => {
                                if (msg.numberOfBytes >= @sizeOf(UdpDiscoverResponse)) {
                                    log_msg(.diagnostic, "got udp response\n", .{});
                                } else {
                                    log_msg(.@"error", "expected {} bytes, got {}\n", .{
                                        @sizeOf(UdpDiscoverResponse),
                                        msg.numberOfBytes,
                                    });
                                }
                            },

                            _ => |val| {
                                log_msg(.@"error", "invalid packet type: {}\n", .{val});
                            },
                        }
                    } else {
                        log_msg(.@"error", "Invalid packet magic: {X:0>2}{X:0>2}{X:0>2}{X:0>2}\n", .{
                            message.header.magic[0],
                            message.header.magic[1],
                            message.header.magic[2],
                            message.header.magic[3],
                        });
                    }
                }
            } else |err| {
                log_msg(.@"error", "failed to receive udp message: {}\n", .{err});
            }
        }
        if (self.socket_set.isReadyRead(self.tcp_sock)) {
            const socket = self.tcp_sock.accept() catch |err| return mapNetworkError(err);
            errdefer socket.close();

            const ep = socket.getRemoteEndPoint() catch |err| return mapNetworkError(err);

            const node = try self.allocator.create(ConnectionNode);
            errdefer self.allocator.destroy(node);

            node.* = ConnectionNode.init(dunstblick_Connection.init(self, socket, ep));
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

                    self.onConnected.invoke(.{
                        @ptrCast(*c.dunstblick_Provider, self),
                        @ptrCast(*c.dunstblick_Connection, &item.data),
                        item.data.header.?.clientName,
                        item.data.header.?.password,
                        item.data.screenResolution,
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

pub const dunstblick_Object = struct {
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

    pub fn setProperty(self: *Self, name: PropertyName, value: Value) !void {
        try self.commandbuffer.writeEnum(@intCast(u8, @enumToInt(value.type)));
        try self.commandbuffer.writeID(name);
        try self.commandbuffer.writeValue(value, false);
    }

    pub fn commit(self: *Self) !void {
        defer self.cancel(); // self will free the memory

        try self.commandbuffer.writeEnum(0);
        try self.connection.send(self.commandbuffer);
    }

    pub fn cancel(self: *Self) void {
        self.commandbuffer.deinit();
        self.connection.provider.allocator.destroy(self);
    }
};

const protocol = protocol_v1;
const protocol_v1 = struct {
    /// Protocol initiating message sent from the display client to
    /// the UI provider.
    const TcpConnectHeader = packed struct {
        const real_magic = [4]u8{ 0x21, 0x06, 0xc1, 0x62 };
        const current_protocol_version: u16 = 1;

        // protocol header, must not be changed or reordered between
        // different protocol versions!
        magic: [4]u8,
        protocol_version: u16,

        // data header
        name: [32]u8,
        password: [32]u8,
        capabilities: u32,
        screenSizeX: u16,
        screenSizeY: u16,
    };

    /// Response from the ui provider to the display client.
    /// Is the direct answer to @ref TcpConnectHeader.
    const TcpConnectResponse = packed struct {
        ///< is `1` if the connection was successful, otherwise `0`.
        success: u32,
        ///< Number of resources that should be transferred to the display client.
        resourceCount: u32,
    };

    /// Followed after the @ref TcpConnectResponse, `resourceCount` descriptors
    /// are transferred to the display client.
    const TcpResourceDescriptor = packed struct {
        ///< The unique resource identifier.
        id: ResourceID,
        ///< The type of the resource.
        type: ResourceKind,
        ///< Size of the resource in bytes.
        size: u32,
        ///< MD5sum of the resource data.
        md5sum: [16]u8,
    };

    /// Followed after the set of @ref TcpResourceDescriptor
    /// the display client answers with the number of required resources.
    const TcpResourceRequestHeader = packed struct {
        request_count: u32,
    };

    /// Sent `request_count` times by the display server after the
    /// @ref TcpResourceRequestHeader.
    const TcpResourceRequest = packed struct {
        id: ResourceID,
    };

    /// Sent after the last @ref TcpResourceRequest for each
    /// requested resource. Each @ref TcpResourceHeader is followed by a
    /// blob containing the resource itself.
    const TcpResourceHeader = packed struct {
        ///< id of the resource
        id: ResourceID,
        ///< size of the transferred resource
        size: u32,
    };
};

const UdpAnnouncementType = enum(u16) {
    UDP_DISCOVER, UDP_RESPOND_DISCOVER, _
};

const UdpHeader = extern struct {
    const Self = @This();

    const real_magic = [4]u8{ 0x73, 0xe6, 0x37, 0x28 };
    magic: [4]u8,
    type: u16,

    fn create(_type: UdpAnnouncementType) Self {
        return Self{
            .magic = real_magic,
            .type = @enumToInt(_type),
        };
    }
};

const UdpDiscover = extern struct {
    header: UdpHeader,
};

const UdpDiscoverResponse = extern struct {
    header: UdpHeader,
    tcp_port: u16,
    length: u16,
    name: [DUNSTBLICK_MAX_APP_NAME_LENGTH]u8,
};

const UdpBaseMessage = extern union {
    header: UdpHeader,
    discover: UdpDiscover,
    discover_response: UdpDiscoverResponse,
};

comptime {
    std.debug.assert(@sizeOf(UdpHeader) == 6);
    std.debug.assert(@sizeOf(UdpDiscover) == 6);
    std.debug.assert(@sizeOf(UdpDiscoverResponse) == 74);
}

const DataReader = struct {
    const Self = @This();

    source: []const u8,
    offset: usize,

    fn init(data: []const u8) Self {
        return Self{
            .source = data,
            .offset = 0,
        };
    }

    fn readByte(self: *Self) !u8 {
        if (self.offset >= self.source.len)
            return error.EndOfStream;
        const value = self.source[self.offset];
        self.offset += 1;
        return value;
    }

    fn readVarUInt(self: *Self) !u32 {
        var number: u32 = 0;

        while (true) {
            const value = try self.readByte();
            number <<= 7;
            number |= value & 0x7F;
            if ((value & 0x80) == 0)
                break;
        }

        return number;
    }

    fn readVarSInt(self: *Self) !i32 {
        return ZigZagInt.decode(try self.readVarUInt());
    }

    fn readRaw(self: *Self, n: usize) ![]const u8 {
        if (self.offset + n > self.source.len)
            return error.EndOfStream;
        const value = self.source[self.offset .. self.offset + n];
        self.offset += n;
        return value;
    }

    fn readNumber(self: *Self) !f32 {
        const bits = try self.readRaw(4);
        return @bitCast(f32, bits[0..4].*);
    }

    fn readValue(self: *Self, _type: c.dunstblick_Type) !Value {
        var value = Value{
            .type = _type,
            .unnamed_3 = undefined,
        };
        const val = &value.unnamed_3;
        switch (_type) {
            .DUNSTBLICK_TYPE_ENUMERATION => val.enumeration = try self.readByte(),

            .DUNSTBLICK_TYPE_INTEGER => val.integer = try self.readVarSInt(),

            .DUNSTBLICK_TYPE_RESOURCE => val.resource = try self.readVarUInt(),

            .DUNSTBLICK_TYPE_OBJECT => val.object = try self.readVarUInt(),

            .DUNSTBLICK_TYPE_NUMBER => val.number = try self.readNumber(),

            .DUNSTBLICK_TYPE_BOOLEAN => val.boolean = ((try self.readByte()) != 0),

            .DUNSTBLICK_TYPE_COLOR => {
                val.color.r = try self.readByte();
                val.color.g = try self.readByte();
                val.color.b = try self.readByte();
                val.color.a = try self.readByte();
            },

            .DUNSTBLICK_TYPE_SIZE => {
                val.size.w = try self.readVarUInt();
                val.size.h = try self.readVarUInt();
            },

            .DUNSTBLICK_TYPE_POINT => {
                val.point.x = try self.readVarSInt();
                val.point.y = try self.readVarSInt();
            },

            // HOW?
            .DUNSTBLICK_TYPE_STRING => return error.NotSupported, // not implemented yet

            .DUNSTBLICK_TYPE_MARGINS => {
                val.margins.left = try self.readVarUInt();
                val.margins.top = try self.readVarUInt();
                val.margins.right = try self.readVarUInt();
                val.margins.bottom = try self.readVarUInt();
            },

            .DUNSTBLICK_TYPE_OBJECTLIST => return error.NotSupported, // not implemented yet

            _ => return error.NotSupported,
        }
        return value;
    }
};

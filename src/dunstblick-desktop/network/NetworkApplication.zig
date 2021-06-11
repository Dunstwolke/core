const std = @import("std");
const zero_graphics = @import("zero-graphics");
const network = @import("network");
const protocol = @import("dunstblick-protocol");
const logger = std.log.scoped(.network_application);

const AppDiscovery = @import("AppDiscovery.zig");
const ApplicationInstance = @import("../gui/ApplicationInstance.zig");
const ApplicationDescription = @import("../gui/ApplicationDescription.zig");

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
    data: std.ArrayList(u8),
    hash: [8]u8,
};

const Self = @This();

flagged_for_deletion: bool = false,
instance: ApplicationInstance,
allocator: *std.mem.Allocator,
arena: std.heap.ArenaAllocator,

socket: ?network.Socket,

remote_end_point: network.EndPoint,

client: protocol.tcp.ClientStateMachine(network.Socket.Writer),

state: State = .unconnected,

screen_size: Size,

resources: std.AutoArrayHashMap(protocol.ResourceID, Resource),

discovery: *AppDiscovery,

pub fn init(self: *Self, allocator: *std.mem.Allocator, app_desc: *const AppDiscovery.Application) !void {
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
    };

    self.socket = try network.Socket.create(std.meta.activeTag(app_desc.address), .tcp);
    errdefer self.socket.?.close();

    self.client = protocol.tcp.ClientStateMachine(network.Socket.Writer).init(allocator, self.socket.?.writer());
    errdefer self.client.deinit();

    self.instance.description.display_name = try self.arena.allocator.dupeZ(u8, self.instance.description.display_name);
    if (self.instance.description.icon) |*icon| {
        icon.* = try self.arena.allocator.dupe(u8, icon.*);
    }

    self.instance.status = .{ .starting = "Connecting..." };

    if (std.builtin.os.tag == .linux) {
        var flags = try std.os.fcntl(self.socket.?.internal, std.os.F_GETFL, 0);
        flags |= @as(usize, std.os.O_NONBLOCK);
        _ = try std.os.fcntl(self.socket.?.internal, std.os.F_SETFL, flags);
    }

    try self.discovery.socket_set.add(self.socket.?, .{ .read = true, .write = true });
    errdefer self.discovery.socket_set.remove(self.socket.?);

    try self.tryConnect();
}

pub fn deinit(self: *Self) void {
    if (self.socket) |*sock| {
        self.client.deinit();
        sock.close();
    }
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
        if (std.builtin.os.tag == .linux) {
            var flags = try std.os.fcntl(self.socket.?.internal, std.os.F_GETFL, 0);
            flags &= ~@as(usize, std.os.O_NONBLOCK);
            _ = try std.os.fcntl(self.socket.?.internal, std.os.F_SETFL, flags);
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
    logger.info("socket read {}", .{self.state});
    switch (self.state) {
        .unconnected, .socket_connecting => return error.InvalidState,

        .protocol_connecting, .connected => {
            var backing_buffer: [8192]u8 = undefined;

            const len = try self.socket.?.receive(&backing_buffer);

            if (len == 0) {
                self.state = .faulted;
                self.instance.status = .{ .exited = "Lost connection to application." };
                return;
            }

            const buffer = backing_buffer[0..len];

            var offset: usize = 0;
            while (offset < buffer.len) {
                const push_info = try self.client.pushData(buffer[offset..]);
                offset += push_info.consumed;
                if (push_info.event) |event| {
                    logger.debug("received event: {s}", .{@tagName(std.meta.activeTag(event))});
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
                                    .{
                                        .mouse = true,
                                        .keyboard = true,
                                        .touch = true,
                                        .highdpi = false,
                                        .tiltable = false,
                                        .resizable = true,
                                        .req_accessibility = false,
                                    },
                                );
                            }
                        },
                        .connect_response => |info| {
                            // TODO: Request available resources
                            logger.info("server has {} resources, we want none!", .{info.resource_count});
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
                                .data = std.ArrayList(u8).init(self.allocator),
                            };

                            if (info.is_last) {
                                // just request all resources

                                var temp_list = std.ArrayList(protocol.ResourceID).init(self.allocator);
                                defer temp_list.deinit();

                                try temp_list.ensureCapacity(self.resources.count());
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

                                try entry.value_ptr.data.resize(info.data.len);
                                std.mem.copy(u8, entry.value_ptr.data.items, info.data);
                            } else {
                                self.disconnect(null);
                                self.instance.status = .{ .exited = "protocol violation: invalid res" };
                                return;
                            }
                        },
                        .message => |packet| {
                            logger.info("unhandled packet: {}", .{std.fmt.fmtSliceEscapeUpper(packet)});
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
        .faulted => return error.InvalidState,
    }
}

pub fn update(self: *Self, dt: f32) !void {
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
            // we're done now :)
        },
        .faulted => {},
    }
}

pub fn resize(self: *Self, size: Size) !void {
    //
    self.screen_size = size;
}

pub fn render(self: *Self, rectangle: zero_graphics.Rectangle, painter: *zero_graphics.Renderer2D) !void {
    //
}

pub fn processUserInterface(self: *Self, rectangle: zero_graphics.Rectangle, ui: zero_graphics.UserInterface.Builder) zero_graphics.UserInterface.Builder.Error!void {
    const center_rect = rectangle.centered(200, 400);

    var temp_string_buffer: [256]u8 = undefined;

    try ui.panel(center_rect, .{});

    var layout = zero_graphics.UserInterface.VerticalStackLayout.init(center_rect.shrink(4));

    try ui.label(layout.get(24), "Remote Application", .{ .horizontal_alignment = .center });

    try ui.label(layout.get(24), std.fmt.bufPrint(&temp_string_buffer, "End Point: {}", .{self.remote_end_point}) catch "<oom>", .{});
    try ui.label(layout.get(24), "Resources:", .{});
    {
        var it = self.resources.iterator();

        while (it.next()) |res| {
            try ui.label(layout.get(20), std.fmt.bufPrint(&temp_string_buffer, "RES {}: {:.3} of {s}", .{
                @enumToInt(res.key_ptr.*),
                std.fmt.fmtIntSizeBin(res.value_ptr.data.items.len),
                @tagName(res.value_ptr.kind),
            }) catch "<oom>", .{});
        }
    }
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
            else => |e| return error.IoError,
        };
    }

    pub fn resize(instance: *ApplicationInstance, size: Size) ApplicationInstance.Interface.ResizeError!void {
        const self = @fieldParentPtr(Self, "instance", instance);
        try self.resize(size);
    }

    pub fn render(instance: *ApplicationInstance, rectangle: zero_graphics.Rectangle, painter: *zero_graphics.Renderer2D) ApplicationInstance.Interface.RenderError!void {
        const self = @fieldParentPtr(Self, "instance", instance);
        try self.render(rectangle, painter);
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

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

const Self = @This();

flagged_for_deletion: bool = false,
instance: ApplicationInstance,
allocator: *std.mem.Allocator,
arena: std.heap.ArenaAllocator,

socket: network.Socket,

remote_end_point: network.EndPoint,

client: protocol.tcp.ClientStateMachine(network.Socket.Writer),

state: State = .unconnected,

screen_size: Size,

pub fn init(self: *Self, allocator: *std.mem.Allocator, app_desc: *const AppDiscovery.Application) !void {
    self.* = Self{
        .instance = ApplicationInstance{
            .description = app_desc.description,
            .vtable = ApplicationInstance.Interface.get(Interface),
        },
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .socket = undefined,
        .client = undefined,
        .remote_end_point = network.EndPoint{
            .address = app_desc.address,
            .port = app_desc.tcp_port,
        },
        .screen_size = Size.empty,
    };

    self.socket = try network.Socket.create(std.meta.activeTag(app_desc.address), .tcp);
    errdefer self.socket.close();

    self.client = protocol.tcp.ClientStateMachine(network.Socket.Writer).init(allocator, self.socket.writer());
    errdefer self.client.deinit();

    self.instance.description.display_name = try self.arena.allocator.dupeZ(u8, self.instance.description.display_name);
    if (self.instance.description.icon) |*icon| {
        icon.* = try self.arena.allocator.dupe(u8, icon.*);
    }

    self.instance.status = .{ .starting = "Connecting..." };

    if (std.builtin.os.tag == .linux) {
        var flags = try std.os.fcntl(self.socket.internal, std.os.F_GETFL, 0);
        flags |= @as(usize, std.os.O_NONBLOCK);
        _ = try std.os.fcntl(self.socket.internal, std.os.F_SETFL, flags);
    }
    try self.tryConnect();
}

pub fn isFaulted(self: Self) bool {
    return self.state == .faulted;
}

fn tryConnect(self: *Self) !void {
    if (self.socket.connect(self.remote_end_point)) {
        // remove blocking from socket
        if (std.builtin.os.tag == .linux) {
            var flags = try std.os.fcntl(self.socket.internal, std.os.F_GETFL, 0);
            flags &= ~@as(usize, std.os.O_NONBLOCK);
            _ = try std.os.fcntl(self.socket.internal, std.os.F_SETFL, flags);
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

pub fn notifyWritable(self: *Self) !bool {
    // logger.info("socket write {}", .{self.state});
    switch (self.state) {
        .unconnected => return error.InvalidState,

        .socket_connecting => {
            try self.tryConnect();
            return (self.state != .socket_connecting);
        },

        .protocol_connecting, .connected, .faulted => return false,
    }
}

pub fn notifyReadable(self: *Self) !void {
    logger.info("socket read {}", .{self.state});
    switch (self.state) {
        .unconnected, .socket_connecting => return error.InvalidState,

        .protocol_connecting, .connected => {
            var backing_buffer: [8192]u8 = undefined;

            const len = try self.socket.receive(&backing_buffer);

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
                                self.socket.close();
                                self.state = .faulted;
                            }
                            // TODO: Send auth info if required
                        },
                        .authenticate_result => |data| { //  AuthenticateResult{ .result = Result.success } }
                            if (data.result != .success) {
                                self.instance.status = .{ .exited = switch (data.result) {
                                    .success => unreachable,
                                    .invalid_credentials => "Invalid credentials",
                                } };
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

                            if (info.resource_count > 0) {
                                // Request no resources:
                                try self.client.sendResourceRequest(&[_]protocol.ResourceID{});
                            }
                        },
                        else => logger.info("unhandled event: {}", .{event}),
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

pub fn close(self: *Self) void {
    // self.client.sendMessage("Good bye!") catch {};

    self.socket.close();
    self.state = .faulted;
    self.instance.status = .{ .exited = "DE killed me" };
}

pub fn deinit(self: *Self) void {
    self.client.deinit();
    self.socket.close();
    self.arena.deinit();
    self.* = undefined;
    self.flagged_for_deletion = true;
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

    pub fn close(instance: *ApplicationInstance) void {
        const self = @fieldParentPtr(Self, "instance", instance);
        self.close();
    }

    pub fn deinit(instance: *ApplicationInstance) void {
        const self = @fieldParentPtr(Self, "instance", instance);
        self.deinit();
    }
};

const std = @import("std");
const network = @import("network");
const protocol = @import("dunstblick-protocol");
const logger = std.log.scoped(.app_discovery);

const ApplicationDescription = @import("../gui/ApplicationDescription.zig");
const ApplicationInstance = @import("../gui/ApplicationInstance.zig");

const NetworkApplication = @import("NetworkApplication.zig");

const Self = @This();

const AppList = std.TailQueue(Application);
const AppNode = std.TailQueue(Application).Node;

const AppInstanceList = std.TailQueue(NetworkApplication);
const AppInstanceNode = std.TailQueue(NetworkApplication).Node;

const multicast_ep = network.EndPoint{
    .address = network.Address{
        .ipv4 = network.Address.IPv4.init(224, 0, 0, 1),
    },
    .port = protocol.udp.port,
};

/// The time period in which we will send out a discover message
const scan_period = 100 * std.time.ns_per_ms;

/// The time period how long a application will stay alive after it was discovered.
const keep_alive_period = 1000 * std.time.ns_per_ms;

allocator: *std.mem.Allocator,
arena: std.heap.ArenaAllocator,

multicast_sock: network.Socket,
socket_set: network.SocketSet,

app_list: AppList,
free_app_list: AppList,

active_apps: AppInstanceList,

/// This stores the time stamp when the next scan update will happen.
next_scan: i128,

pub fn init(allocator: *std.mem.Allocator) !Self {
    var multicast_sock = try network.Socket.create(.ipv4, .udp);
    errdefer multicast_sock.close();

    var socket_set = try network.SocketSet.init(allocator);
    errdefer socket_set.deinit();

    try socket_set.add(multicast_sock, .{
        .read = true,
        .write = false,
    });

    return Self{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),

        .multicast_sock = multicast_sock,
        .socket_set = socket_set,

        .app_list = .{},
        .free_app_list = .{},

        .active_apps = .{},

        .next_scan = std.time.nanoTimestamp(),
    };
}

pub fn deinit(self: *Self) void {
    while (self.active_apps.first) |node| {
        self.destroyApplication(node);
    }
    self.socket_set.deinit();
    self.multicast_sock.close();
    self.arena.deinit();
    self.* = undefined;
}

fn destroyApplication(self: *Self, node: *AppInstanceNode) void {
    if (!node.data.flagged_for_deletion) {
        node.data.deinit();
    }
    self.active_apps.remove(node);
    self.allocator.destroy(node);
}

fn allocApp(self: *Self) !*AppNode {
    const node = if (self.free_app_list.popFirst()) |n|
        n
    else
        try self.arena.allocator.create(AppNode);
    node.* = .{
        .data = undefined,
    };
    return node;
}

fn freeApp(self: *Self, app_node: *AppNode) void {
    self.app_list.remove(app_node);
    self.free_app_list.append(app_node);

    app_node.data.strings_buffer.deinit();

    app_node.data = undefined;
}

pub fn update(self: *Self) !void {
    const time_stamp = std.time.nanoTimestamp();

    // Clean up all deleted applications:
    {
        var it = self.active_apps.first;
        while (it) |node| {
            it = node.next;
            if (node.data.flagged_for_deletion) {
                self.destroyApplication(node);
            }
        }
    }

    if (time_stamp >= self.next_scan) {
        var discover_msg = protocol.udp.Discover{
            .header = protocol.udp.Header.create(.discover),
        };
        _ = try self.multicast_sock.sendTo(multicast_ep, std.mem.asBytes(&discover_msg));

        if (time_stamp - self.next_scan > 2 * scan_period) {
            // we are more than 3 scan periods behind, let's just catch
            // up by discarding all missed scans
            self.next_scan = time_stamp + scan_period;
        } else {
            // if we are still only slightly behind or on time,
            // let's continue scanning in fixed periods.
            self.next_scan += scan_period;
        }
    }

    while (true) {
        // check if we received some messages, if not: stop

        const count = try network.waitForSocketEvent(&self.socket_set, 0);
        if (count == 0)
            break;

        {
            var it = self.active_apps.first;
            while (it) |node| : (it = node.next) {
                std.debug.assert(node.data.flagged_for_deletion == false);

                if (node.data.socket) |sock| {
                    if (self.socket_set.isReadyWrite(sock)) {
                        try node.data.notifyWritable();
                    }
                    if (self.socket_set.isReadyRead(sock)) {
                        try node.data.notifyReadable();
                    }
                }
            }
        }

        if (self.socket_set.isReadyRead(self.multicast_sock)) {
            var message: protocol.udp.Message = undefined;
            const receive_info = try self.multicast_sock.receiveFrom(std.mem.asBytes(&message));
            if (receive_info.numberOfBytes >= @sizeOf(protocol.udp.DiscoverResponse) and message.header.type == .respond_discover) {
                const resp = &message.discover_response;

                const address = receive_info.sender.address;
                const udp_port = receive_info.sender.port;
                const tcp_port = resp.tcp_port;

                const app_node = blk: {
                    var it = self.app_list.first;
                    while (it) |node| : (it = node.next) {
                        if (node.data.tcp_port != tcp_port)
                            continue;
                        if (node.data.udp_port != udp_port)
                            continue;
                        if (!node.data.address.eql(address))
                            continue;
                        break :blk node;
                    }
                    break :blk null;
                };

                const updated_app = if (app_node) |node| blk: {
                    break :blk node;
                } else blk: {
                    const node = try self.allocApp();
                    node.data = Application{
                        .discovery = self,
                        .description = ApplicationDescription{
                            .display_name = undefined,
                            .icon = null,
                            .vtable = ApplicationDescription.Interface.get(Application),
                            .state = .ready,
                        },
                        .address = address,
                        .tcp_port = tcp_port,
                        .udp_port = udp_port,
                        .last_seen = undefined,
                        .app_description = null,
                        .strings_buffer = std.ArrayList(u8).init(self.allocator),
                    };
                    self.app_list.append(node);
                    break :blk node;
                };
                errdefer self.freeApp(updated_app);

                try updated_app.data.setStrings(
                    resp.getName(),
                    if (resp.getDescriptionPtr()) |desc| desc.get() else null,
                    if (resp.getIconPtr()) |icon| icon.get() else null,
                );

                updated_app.data.last_seen = time_stamp;

                // The app removal was requested, but we would've re-added it here
                // anyways, so we can just *not* remove it
                updated_app.data.was_removal_requested = false;
            }
        }
    }

    {
        var iter = self.app_list.first;
        while (iter) |node| {
            iter = node.next;

            if (node.data.was_removal_requested) {
                self.freeApp(node);
            } else {
                node.data.description.state = if ((time_stamp - node.data.last_seen) <= keep_alive_period)
                    ApplicationDescription.State.ready
                else
                    ApplicationDescription.State.gone;
            }
        }
    }
}

pub fn iterator(self: Self) Iterator {
    return Iterator{
        .it = self.app_list.first,
    };
}

pub const Iterator = struct {
    it: ?*AppNode,

    pub fn next(self: *@This()) ?*Application {
        const current = self.it;
        if (current) |c| {
            self.it = c.next;
        }
        return if (current) |c|
            &c.data
        else
            null;
    }
};

pub const Application = struct {
    description: ApplicationDescription,

    address: network.Address,
    tcp_port: u16,
    udp_port: u16,

    last_seen: i128,

    app_description: ?[:0]const u8,

    strings_buffer: std.ArrayList(u8),
    was_removal_requested: bool = false,

    discovery: *Self,

    pub fn spawn(desc: *ApplicationDescription, allocator: *std.mem.Allocator) ApplicationDescription.Interface.SpawnError!*ApplicationInstance {
        const self = @fieldParentPtr(Application, "description", desc);

        const node = try self.discovery.allocator.create(AppInstanceNode);
        errdefer self.discovery.allocator.destroy(node);

        NetworkApplication.init(&node.data, allocator, self) catch |err| {
            logger.err("failed to start app: {}", .{err});
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.IoError,
            };
        };

        self.discovery.active_apps.append(node);

        return &node.data.instance;
    }

    /// Requests the removal of this application.
    /// Apps aren't automatically removed from the application list
    /// as they are still displayed in the menu and it could cause evil
    /// misclicks when a app is removed in the moment a user clicks. This
    /// function will destroy the application state.
    pub fn destroy(desc: *ApplicationDescription) ApplicationDescription.Interface.DestroyError!void {
        const self = @fieldParentPtr(Application, "description", desc);
        self.was_removal_requested = true;
    }

    /// Allocates or resizes enough memory to store application name and potentially the icon and description text.
    fn setStrings(self: *@This(), app_name: []const u8, description: ?[]const u8, icon: ?[]const u8) !void {
        var len = app_name.len + 1;
        if (description) |data|
            len += data.len + 1;
        if (icon) |data|
            len += data.len;

        try self.strings_buffer.resize(len);

        var start: usize = 0;
        {
            std.mem.copy(u8, self.strings_buffer.items[start .. start + app_name.len], app_name);
            self.strings_buffer.items[start + app_name.len] = 0;
            self.description.display_name = self.strings_buffer.items[start .. start + app_name.len :0];
            start += app_name.len + 1;
        }

        if (description) |desc| {
            std.mem.copy(u8, self.strings_buffer.items[start .. start + desc.len], desc);
            self.strings_buffer.items[start + desc.len] = 0;
            self.app_description = self.strings_buffer.items[start .. start + desc.len :0];
            start += desc.len + 1;
        } else {
            self.app_description = null;
        }

        if (icon) |data| {
            std.mem.copy(u8, self.strings_buffer.items[start .. start + data.len], data);
            self.description.icon = self.strings_buffer.items[start .. start + data.len];
            start += data.len;
        } else {
            self.description.icon = null;
        }
    }
};

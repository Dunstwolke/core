const std = @import("std");
const network = @import("network");
const protocol = @import("dunstblick-protocol");

pub const Application = struct {
    name: []const u8,

    address: network.Address,
    tcp_port: u16,
    udp_port: u16,
};

pub const DiscoveryResult = struct {
    const Self = @This();
    arena: std.heap.ArenaAllocator,
    applications: []Application,

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

const multicast_ep = network.EndPoint{
    .address = network.Address{
        .ipv4 = network.Address.IPv4.init(224, 0, 0, 1),
    },
    .port = 1309,
};

fn thread_proc(allocator: *std.mem.Allocator) !void {
    var multicast_sock = try network.Socket.create(.ipv4, .udp);
    defer multicast_sock.close();

    var socket_set = try network.SocketSet.init(allocator);
    defer socket_set.deinit();

    try socket_set.add(multicast_sock, .{
        .read = true,
        .write = false,
    });

    while (!@atomicLoad(bool, &shutdown_requested, .Acquire)) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var new_clients = std.ArrayList(Application).init(&arena.allocator);
        errdefer new_clients.deinit();

        std.debug.print("Starting discovery…\n", .{});

        var round: usize = 0;
        while (round < 10) : (round += 1) {
            var discover_msg = protocol.udp.Discover{
                .header = protocol.udp.Header.create(.discover),
            };

            _ = try multicast_sock.sendTo(multicast_ep, std.mem.asBytes(&discover_msg));

            while (true) {
                const count = try network.waitForSocketEvent(
                    &socket_set,
                    50 * std.time.ns_per_ms,
                );

                if (count == 0) // timeout situation
                    break;

                if (socket_set.isReadyRead(multicast_sock)) {
                    var message: protocol.udp.Message = undefined;
                    const receive_info = try multicast_sock.receiveFrom(std.mem.asBytes(&message));

                    if (receive_info.numberOfBytes >= @sizeOf(protocol.udp.DiscoverResponse) and message.header.type == .respond_discover) {
                        const resp = &message.discover_response;

                        if (resp.length < resp.name.len) {
                            resp.name[resp.length] = 0;
                        }

                        var app = Application{
                            .name = "",
                            .address = receive_info.sender.address,
                            .udp_port = receive_info.sender.port,
                            .tcp_port = resp.tcp_port,
                        };

                        var found = false;
                        for (new_clients.items) |existing_app| {
                            if (existing_app.tcp_port != app.tcp_port)
                                continue;
                            if (existing_app.udp_port != app.udp_port)
                                continue;
                            if (!existing_app.address.eql(app.address))
                                continue;
                            found = true;
                            break;
                        }
                        if (found)
                            continue;

                        app.name = try std.mem.dupe(&arena.allocator, u8, resp.name[0..(std.mem.indexOf(u8, &resp.name, "\x00") orelse resp.name.len)]);

                        try new_clients.append(app);
                    }
                }
            }
        }

        std.sort.sort(Application, new_clients.items, {}, struct {
            fn lessThan(context: void, lhs: Application, rhs: Application) bool {
                return (std.mem.order(u8, lhs.name, rhs.name) == .lt);
            }
        }.lessThan);

        //        size_t idx = 0;
        //        for (auto const & client : new_clients) {
        //            fprintf(stderr,
        //                    "[%lu] %s:\n"
        //                    "\tname: %s\n"
        //                    "\tport: %d\n",
        //                    idx++,
        //                    xnet::to_string(client.udp_ep).c_str(),
        //                    client.name.c_str(),
        //                    client.tcp_port);
        //            fflush(stderr);
        //        }

        {
            // std::lock_guard<std::mutex> lock{discovered_clients_lock};
            // discovered_clients = std::move(new_clients);
        }

        std.debug.print("Found {} clients!\n", .{
            new_clients.items.len,
        });

        std.time.sleep(1 * std.time.ns_per_s);
    }
}

var global_allocator: *std.mem.Allocator = undefined;
var current_thread: ?*std.Thread = null;

var shutdown_requested: bool = false;

pub fn init(allocator: *std.mem.Allocator) void {
    global_allocator = allocator;
}

pub fn start() !void {
    if (current_thread != null)
        return;
    shutdown_requested = false;
    current_thread = try std.Thread.spawn(global_allocator, thread_proc);
}

pub fn stop() void {
    if (current_thread) |thread| {
        shutdown_requested = true;
        thread.wait();
    }
}

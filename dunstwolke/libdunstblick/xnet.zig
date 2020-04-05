const std = @import("std");

comptime {
    std.debug.assert(@sizeOf(std.os.sockaddr) >= @sizeOf(std.os.sockaddr_in));
    // std.debug.assert(@sizeOf(std.os.sockaddr) >= @sizeOf(std.os.sockaddr_in6));
}

pub const Address = union(AddressFamily) {
    ipv4: IPv4,
    ipv6: IPv6,

    pub const IPv4 = struct {
        const Self = @This();

        pub const any = IPv4.init(0, 0, 0, 0);
        pub const broadcast = IPv4.init(255, 255, 255, 255);

        value: [4]u8,

        pub fn init(a: u8, b: u8, c: u8, d: u8) Self {
            return Self{
                .value = [4]u8{ a, b, c, d },
            };
        }

        pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: var) !void {
            try out_stream.print("{}.{}.{}.{}", .{
                value.value[0],
                value.value[1],
                value.value[2],
                value.value[3],
            });
        }
    };

    pub const IPv6 = struct {
        const Self = @This();

        pub const any = Self{};

        pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: var) !void {
            unreachable;
        }
    };

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: var) !void {
        switch (value) {
            .ipv4 => |a| try a.format(fmt, options, out_stream),
            .ipv6 => |a| try a.format(fmt, options, out_stream),
        }
    }
};

pub const AddressFamily = enum {
    const Self = @This();

    ipv4,
    ipv6,

    fn toNativeAddressFamily(af: Self) u32 {
        return switch (af) {
            .ipv4 => std.os.AF_INET,
            .ipv6 => std.os.AF_INET6,
        };
    }

    fn fromNativeAddressFamily(af: i32) !Self {
        return switch (af) {
            std.os.AF_INET => .ipv4,
            std.os.AF_INET6 => .ipv6,
            else => return error.UnsupportedAddressFamily,
        };
    }
};

pub const Protocol = enum {
    const Self = @This();

    tcp,
    udp,

    fn toSocketType(proto: Self) u32 {
        return switch (proto) {
            .tcp => std.os.SOCK_STREAM,
            .udp => std.os.SOCK_DGRAM,
        };
    }
};

pub const EndPoint = struct {
    const Self = @This();

    address: Address,
    port: u16,

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_stream: var) !void {
        try out_stream.print("{}:{}", .{
            value.address,
            value.port,
        });
    }

    fn fromSocketAddress(src: *align(4) const std.os.sockaddr, size: usize) !Self {
        switch (src.family) {
            std.os.AF_INET => {
                if (size < @sizeOf(std.os.sockaddr_in))
                    return error.InsufficientBytes;
                const value = @ptrCast(*const std.os.sockaddr_in, src);
                return EndPoint{
                    .port = std.mem.bigToNative(u16, value.port),
                    .address = Address{
                        .ipv4 = Address.IPv4{
                            .value = @bitCast([4]u8, value.addr),
                        },
                    },
                };
            },
            std.os.AF_INET6 => {
                unreachable;
            },
            else => return error.UnsupportedAddressFamily,
        }
    }

    fn toSocketAddress(self: Self) std.os.sockaddr {
        var result: std.os.sockaddr align(8) = undefined;
        switch (self.address) {
            .ipv4 => |addr| {
                @ptrCast(*std.os.sockaddr_in, &result).* = std.os.sockaddr_in{
                    .family = std.os.AF_INET,
                    .port = std.mem.nativeToBig(u16, self.port),
                    .addr = @bitCast(u32, addr.value),
                    .zero = [_]u8{0} ** 8,
                };
            },
            .ipv6 => |addr| {
                unreachable;
            },
        }
        return result;
    }
};

pub const Socket = struct {
    pub const Error = error{};
    const Self = @This();

    const NativeSocket = if (std.builtin.os.tag == .windows) @compileError("windows not supported yet") else std.os.fd_t;

    family: AddressFamily,
    internal: NativeSocket,

    pub fn create(family: AddressFamily, protocol: Protocol) !Self {
        return Self{
            .family = family,
            .internal = try std.os.socket(family.toNativeAddressFamily(), protocol.toSocketType(), 0),
        };
    }

    pub fn close(self: Self) void {
        std.os.close(self.internal);
    }

    pub fn bind(self: Self, ep: EndPoint) !void {
        var sockaddr = ep.toSocketAddress();
        try std.os.bind(self.internal, &sockaddr, @sizeOf(@TypeOf(sockaddr)));
    }

    pub fn bindToPort(self: Self, port: u16) !void {
        return switch (self.family) {
            .ipv4 => self.bind(EndPoint{
                .address = Address{ .ipv4 = Address.IPv4.any },
                .port = port,
            }),
            .ipv6 => self.bind(EndPoint{
                .address = Address{ .ipv6 = Address.IPv6.any },
                .port = port,
            }),
        };
    }

    /// Makes this socket a TCP server and allows others to connect to
    /// this socket.
    /// Call `accept()` to handle incoming connections.
    pub fn listen(self: Self) !void {
        try std.os.listen(self.internal, 0);
    }

    /// Waits until a new TCP client connects to this socket and accepts the incoming TCP connection.
    /// This function is only allowed for a bound TCP socket. `listen()` must have been called before!
    pub fn accept(self: Self) !Socket {
        var addr: std.os.sockaddr = undefined;
        var addr_size: std.os.socklen_t = @sizeOf(std.os.sockaddr);

        const fd = try std.os.accept4(self.internal, &addr, &addr_size, 0);
        errdefer std.os.close(fd);

        return Socket{
            .family = try AddressFamily.fromNativeAddressFamily(addr.family),
            .internal = fd,
        };
    }

    pub fn send(self: Self, data: []const u8) !usize {
        unreachable;
    }

    pub fn receive(self: Self, data: []u8) !usize {
        unreachable;
    }

    /// Sets the socket option `SO_REUSEPORT` which allows
    /// multiple bindings of the same socket to the same address
    /// on UDP sockets and allows quicker re-binding of TCP sockets.
    pub fn enablePortReuse(self: Self, enabled: bool) !void {
        var opt: c_int = if (enabled) 1 else 0;
        try std.os.setsockopt(self.internal, std.os.SOL_SOCKET, std.os.SO_REUSEADDR, std.mem.asBytes(&opt));
    }

    /// Retrieves the end point to which the socket is bound.
    pub fn getLocalEndPoint(self: Self) !EndPoint {
        var addr: std.os.sockaddr align(4) = undefined;
        var size: std.os.socklen_t = @sizeOf(@TypeOf(addr));

        try std.os.getsockname(self.internal, &addr, &size);

        return try EndPoint.fromSocketAddress(&addr, size);
    }

    /// Retrieves the end point to which the socket is connected.
    pub fn getRemoteEndPoint(self: Self) !EndPoint {
        var addr: std.os.sockaddr align(4) = undefined;
        var size: std.os.socklen_t = @sizeOf(@TypeOf(addr));

        try getpeername(self.internal, &addr, &size);

        return try EndPoint.fromSocketAddress(&addr, size);
    }

    pub const MulticastGroup = struct {
        interface: Address.IPv4,
        group: Address.IPv4,
    };
    pub fn joinMulticastGroup(self: Self, group: MulticastGroup) !void {
        const ip_mreq = extern struct {
            imr_multiaddr: u32,
            imr_address: u32,
            imr_ifindex: u32,
        };

        const request = ip_mreq{
            .imr_multiaddr = @bitCast(u32, group.group.value),
            .imr_address = @bitCast(u32, group.interface.value),
            .imr_ifindex = 0, // this cannot be crossplatform, so we set it to zero
        };

        const IP_ADD_MEMBERSHIP = 35;

        try std.os.setsockopt(self.internal, std.os.SOL_SOCKET, IP_ADD_MEMBERSHIP, std.mem.asBytes(&request));
    }

    pub fn inStream(self: Self) std.io.InStream(Socket, Error, receive) {
        return .{
            .context = self,
        };
    }

    pub fn outStream(self: Self) std.io.OutStream(Socket, Error, send) {
        return .{
            .context = self,
        };
    }
};

pub const SocketEvent = struct {
    read: bool,
    write: bool,
    fault: bool = false,
};

const OSLogic = switch (std.builtin.os.tag) {
    .linux => struct {
        const Self = @This();
        // use poll on linux

        fds: std.ArrayList(std.os.pollfd),

        fn init(allocator: *std.mem.Allocator) Self {
            return Self{
                .fds = std.ArrayList(std.os.pollfd).init(allocator),
            };
        }

        fn deinit(self: Self) void {
            self.fds.deinit();
        }

        fn clear(self: *Self) void {
            self.fds.shrink(0);
        }

        fn add(self: *Self, sock: Socket, events: SocketEvent) !void {
            var mask: i16 = 0;

            if (events.read)
                mask |= std.os.POLLIN;
            if (events.write)
                mask |= std.os.POLLOUT;
            if (events.fault)
                mask |= std.os.POLLERR;

            for (self.fds.items) |*pfd| {
                if (pfd.fd == sock.internal) {
                    pfd.events |= mask;
                    return;
                }
            }

            try self.fds.append(std.os.pollfd{
                .fd = sock.internal,
                .events = mask,
                .revents = 0,
            });
        }

        fn remove(self: *Self, sock: Socket) void {
            const index = for (self.fds.items) |item, i| {
                if (item.fd == sock.internal)
                    break i;
            } else null;

            if (index) |idx| {
                self.fds.removeSwap(idx);
            }
        }

        fn checkMaskAnyBit(self: Self, sock: Socket, mask: i16) bool {
            for (self.fds.items) |item| {
                if (item.fd != sock.internal)
                    continue;

                if ((item.revents & mask) != 0)
                    return true;

                return false;
            }
            return false;
        }

        fn isReadyRead(self: Self, sock: Socket) bool {
            return self.checkMaskAnyBit(sock, std.os.POLLIN);
        }

        fn isReadyWrite(self: Self, sock: Socket) bool {
            return self.checkMaskAnyBit(sock, std.os.POLLOUT);
        }

        fn isFaulted(self: Self, sock: Socket) bool {
            return self.checkMaskAnyBit(sock, std.os.POLLERR);
        }
    },
    else => @compileError("unsupported os " ++ @tagName(std.builtin.os.tag) ++ " for SocketSet!"),
};

/// A set of sockets that can be used to query socket readiness.
pub const SocketSet = struct {
    const Self = @This();

    internal: OSLogic,

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .internal = OSLogic.init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.internal.deinit();
    }

    pub fn clear(self: *Self) void {
        self.internal.clear();
    }

    pub fn add(self: *Self, sock: Socket, events: SocketEvent) !void {
        try self.internal.add(sock, events);
    }

    pub fn remove(self: *Self, sock: Socket) void {
        self.internal.remove(sock);
    }

    pub fn isReadyRead(self: Self, sock: Socket) bool {
        return self.internal.isReadyRead(sock);
    }

    pub fn isReadyWrite(self: Self, sock: Socket) bool {
        return self.internal.isReadyWrite(sock);
    }

    pub fn isFaulted(self: Self, sock: Socket) bool {
        return self.internal.isFaulted(sock);
    }
};

/// Waits until sockets in SocketSet are ready to read/write or have a fault condition.
/// If `timeout` is not `null`, it describes a timeout in nanoseconds until the function
/// should return.
/// Note that `timeout` granularity may not be available in nanoseconds and larger
/// granularities are used.
/// If the requested timeout interval requires a finer granularity than the implementation supports, the
/// actual timeout interval shall be rounded up to the next supported value.
pub fn waitForSocketEvent(set: *SocketSet, timeout: ?u64) !usize {
    switch (std.builtin.os.tag) {
        .linux => return try std.os.poll(
            set.internal.fds.items,
            if (timeout) |val| @intCast(i32, (val + std.time.millisecond - 1) / std.time.millisecond) else -1,
        ),
        else => @compileError("unsupported os " ++ @tagName(std.builtin.os.tag) ++ " for SocketSet!"),
    }
}

const GetPeerNameError = error{
    /// Insufficient resources were available in the system to perform the operation.
    SystemResources,
    NotConnected,
} || std.os.UnexpectedError;

fn getpeername(sockfd: std.os.fd_t, addr: *std.os.sockaddr, addrlen: *std.os.socklen_t) GetPeerNameError!void {
    switch (std.os.errno(std.os.system.getsockname(sockfd, addr, addrlen))) {
        0 => return,
        else => |err| return std.os.unexpectedErrno(err),

        std.os.EBADF => unreachable, // always a race condition
        std.os.EFAULT => unreachable,
        std.os.EINVAL => unreachable, // invalid parameters
        std.os.ENOTSOCK => unreachable,
        std.os.ENOBUFS => return error.SystemResources,
        std.os.ENOTCONN => return error.NotConnected,
    }
}

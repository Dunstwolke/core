const std = @import("std");

pub const Address = union(AddressFamily) {
    ipv4: IPv4,
    ipv6: void,

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
    };

    pub const IPv6 = struct {
        pub const any = {};
    };
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

    fn fromSocketAddress(src: *align(4) const std.os.sockaddr, size: usize) !Self {
        switch (src.family) {
            std.os.AF_INET => {
                if (size < @sizeOf(std.os.sockaddr_in))
                    return error.InsufficientBytes;
                const value = @ptrCast(*const std.os.sockaddr_in, &src);
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

    pub fn listen(self: Self) !void {
        try std.os.listen(self.internal, 0);
    }

    pub fn accept(self: Self) !Socket {
        unreachable;
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

    /// Retrieves the end point to which the socket is bound at the moment.
    pub fn getLocalEndPoint(self: Self) !EndPoint {
        var addr: std.os.sockaddr align(4) = undefined;
        var size: std.os.socklen_t = @sizeOf(@TypeOf(addr));

        try std.os.getsockname(self.internal, &addr, &size);

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

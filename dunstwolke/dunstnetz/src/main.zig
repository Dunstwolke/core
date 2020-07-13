const std = @import("std");

const port_number = 16158;

const Address = packed struct {
    value: [6]u8,

    pub fn init(a0: u8, a1: u8, a2: u8, a3: u8, a4: u8, a5: u8) Address {
        return Address{
            .value = [_]u8{ a0, a1, a2, a3, a4, a5 },
        };
    }

    fn parse(str: []const u8) !Address {
        var iter = std.mem.separate(str, ":");
        comptime var i = 0;
        var addr: Address = undefined;
        inline while (i < 6) : (i += 1) {
            addr.value[i] = try std.fmt.parseInt(u8, iter.next() orelse return error.InvalidAddress, 16);
        }
        return addr;
    }

    fn eql(a: Address, b: Address) bool {
        return std.mem.eql(u8, a.value, b.value);
    }

    pub fn format(self: Address, comptime fmt: []const u8, options: std.fmt.FormatOptions, context: anytype, comptime Errors: type, output: fn (@typeOf(context), []const u8) Errors!void) Errors!void {
        try std.fmt.format(context, Errors, output, "{X:0^2}:{X:0^2}:{X:0^2}:{X:0^2}:{X:0^2}:{X:0^2}", self.value[0], self.value[1], self.value[2], self.value[3], self.value[4], self.value[5]);
    }

    const broadcast = Address.init(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF);
};

test "Address.parse" {
    var addr = try Address.parse("aa:bb:cc:dd:ee:ff");
    std.debug.assert(addr[0] == 0xAA);
    std.debug.assert(addr[1] == 0xBB);
    std.debug.assert(addr[2] == 0xCC);
    std.debug.assert(addr[3] == 0xDD);
    std.debug.assert(addr[4] == 0xEE);
    std.debug.assert(addr[5] == 0xFF);
}
const PacketFlags = packed struct {
    reliable: u1,
    ack: u1,
    _: u6 = 0,
};

comptime {
    std.debug.assert(@sizeOf(PacketFlags) == 1);
}

fn calculateChecksum(data: []const u8) u16 {
    var cs: u16 = 0;
    for (data) |b| {
        _ = @subWithOverflow(u16, cs, b, &cs);
    }
    return cs;
}

// BUG: with "packed", the struct will not be handled correctly.
const PacketHeader = extern struct {
    const size = @sizeOf(@This());

    /// sender address
    src: Address,

    /// receiver address
    dst: Address,

    /// information about the contents of this packet.
    flags: PacketFlags,

    /// length of the data stream behind this header.
    len: u8,

    /// constantly incrementing sequence number of the packets. this is used to ACK messages.
    sequence: u16,

    /// sum this with all bytes in the payload. must be zero then
    checksum: u16,
};

fn LinkedList(comptime T: type) type {
    std.debug.assert(@typeId(std.meta.fieldInfo(T, "next").field_type) == .Optional);
    std.debug.assert(@typeId(std.meta.fieldInfo(T, "previous").field_type) == .Optional);
    return struct {
        const Self = @This();

        front: ?*T,
        back: ?*T,
        mutex: std.Mutex,

        fn init() Self {
            return Self{
                .front = null,
                .back = null,
                .mutex = std.Mutex.init(),
            };
        }

        fn pushFront(self: *Self, value: *T) void {
            var lock = self.mutex.acquire();
            defer lock.release();

            value.previous = null;
            value.next = self.front;

            if (self.front) |front| {
                front.previous = value;
            }
            self.front = value;
            if (self.back == null) {
                self.back = value;
            }
        }

        fn pushBack(self: *Self, value: *T) void {
            var lock = self.mutex.acquire();
            defer lock.release();

            value.previous = self.back;
            value.next = null;

            if (self.back) |back| {
                back.next = value;
            }
            self.back = value;
            if (self.front == null) {
                self.front = value;
            }
        }

        fn popFront(self: *Self) ?*T {
            var lock = self.mutex.acquire();
            defer lock.release();

            if (self.front) |front| {
                var element = front;
                if (front.next) |new_front| {
                    new_front.previous = null;
                    std.debug.assert(self.back != element);
                }
                if (self.back == element) {
                    self.back = null;
                }
                self.front = front.next;
                std.debug.assert(element.previous == null); // just a safety check
                element.next = null;
                return element;
            } else {
                return null;
            }
        }

        fn popBack(self: *Self) ?*T {
            var lock = self.mutex.acquire();
            defer lock.release();

            if (self.back) |back| {
                var element = back;
                if (back.previous) |new_back| {
                    new_back.next = null;
                    std.debug.assert(self.front != element);
                }
                if (self.front == element) {
                    self.front = null;
                }
                self.back = element.previous;
                std.debug.assert(element.next == null); // just a safety check
                element.previous = null;
                return element;
            } else {
                return null;
            }
        }

        /// removes an arbitrary element from the list.
        fn remove(self: *Self, element: *T) void {
            var lock = self.mutex.acquire();
            defer lock.release();

            if (element == self.front) {
                _ = self.popFront();
            } else if (element == self.back) {
                _ = self.popBack();
            } else {
                if (element.previous) |pre| {
                    pre.next = element.next;
                }
                if (element.next) |nxt| {
                    nxt.previous = element.previous;
                }
                element.next = null;
                element.previous = null;
            }
        }
    };
}

const Connection = struct {
    const Self = @This();

    const Packet = struct {
        available: usize,

        /// stores the full message including the PacketHeader.
        /// this means the array must have the same alignment as
        /// PacketHeader
        data: [250]u8 align(@alignOf(PacketHeader)) = undefined,

        /// used for enqueueing reliable packets into the "resend list" or received packets into the "received list".
        /// a packet with `next != null` must never be `available!=0`!
        next: ?*Packet = null,
        previous: ?*Packet = null,

        /// counts the number of retransmissions
        retryCount: u8 = 0,

        /// timestamp of next retransmission if any
        retransmitTimestamp: u64 = 0,

        fn returnToPool(self: *Packet) void {
            // safety-check that the packet is not part of a linked list
            std.debug.assert(self.next == null);
            self.retryCount = 0;
            self.retransmitTimestamp = 0;
            std.mem.set(u8, self.data[0..], 0);

            // we can return a packet to the pool by setting .available to non-zero.
            // this can be done by an atomic operation and does not require a lock
            // because this property is only modified here to "1" and
            // in a critical section to "0".
            if (@atomicRmw(usize, &self.available, .Xchg, 1, .SeqCst) != 0)
                unreachable;
        }

        fn getHeader(self: *Packet) *PacketHeader {
            return @ptrCast(*PacketHeader, &self.data);
        }

        fn getPayloadStorage(self: *Packet) []u8 {
            return self.data[PacketHeader.size..];
        }

        fn getData(self: *Packet) []const u8 {
            return self.data[0 .. self.getHeader().len + PacketHeader.size];
        }

        fn getPayload(self: *Packet) []const u8 {
            return self.data[PacketHeader.size .. self.getHeader().len + PacketHeader.size];
        }
    };

    localAddress: Address,
    sequenceId: u16 = 0,
    socket: std.os.fd_t,
    allocator: *std.mem.Allocator,
    packets: std.ArrayList(*Packet),

    thread: ?*std.Thread = null,
    active: usize = 1,
    mutex: std.Mutex,

    /// contains packets that may require a retransmission
    transmitQueue: LinkedList(Packet),

    ///
    receiveQueue: LinkedList(Packet),

    /// returns a packet that can be used to store sent/received data in.
    /// the packets may be pooled.
    /// the packet returned is immediatly marked as "unavailable" and must be
    /// released in a later action.
    fn getAvailablePacket(self: *Self) !*Packet {
        var lock = self.mutex.acquire();
        defer lock.release();

        for (self.packets.toSlice()) |p| {
            if (@atomicLoad(usize, &p.available, .SeqCst) != 0) {
                if (@atomicRmw(usize, &p.available, .Xchg, 0, .SeqCst) == 0)
                    unreachable;
                return p;
            }
        }

        var packet = try self.allocator.create(Packet);
        packet.* = Packet{
            .available = 0,
        };
        errdefer self.allocator.destroy(packet);

        try self.packets.append(packet);

        return packet;
    }

    /// sends raw data to the socket.
    fn sendRaw(self: *Self, data: []const u8) !void {
        const broadcastAddress = std.net.Address.initIp4(0xFFFFFFFF, port_number).os_addr;

        const len = std.os.linux.sendto(self.socket, data.ptr, data.len, 0, &broadcastAddress, @sizeOf(@typeOf(broadcastAddress)));

        if (len != data.len)
            return error.TransmissionError;
    }

    /// sends an initialized packet. this function takes ownership of that packet.
    fn sendPacket(self: *Self, packet: *Packet) !void {
        const header = packet.getHeader();

        try self.sendRaw(packet.getData());

        if (header.flags.reliable == 1) {
            self.transmitQueue.pushBack(packet);
        } else {
            packet.returnToPool();
        }
    }

    /// sends a new packet to a given receiver. if the receiver is `null`, the packet
    /// will be broadcasted.
    /// note that broadcasts cannot be reliable.
    pub fn send(self: *Self, receiver: ?Address, data: []const u8, reliable: bool) !void {
        if (receiver == null and reliable == true)
            return error.ReliableBroadcastNotSupported;

        // 250 is the maximum message size that ESP-NOW! allows, so
        // we are restricted to this.
        if (data.len > 250 - PacketHeader.size)
            return error.MessageTooLong;

        const target = receiver orelse Address.broadcast;
        if (Address.eql(target, self.localAddress))
            return error.MessageToSelf;

        var packet = try self.getAvailablePacket();

        packet.getHeader().* = PacketHeader{
            .src = self.localAddress,
            .dst = target,
            .flags = PacketFlags{
                .reliable = if (reliable) 1 else 0,
                .ack = 0,
            },
            .len = @truncate(u8, data.len),
            .sequence = self.sequenceId,
            .checksum = calculateChecksum(data),
        };
        _ = @addWithOverflow(u16, self.sequenceId, 1, &self.sequenceId);

        std.mem.copy(u8, packet.getPayloadStorage(), data);

        try self.sendPacket(packet);
    }

    fn init(_allocator: *std.mem.Allocator, address: Address) !Connection {
        var sock = try std.os.socket(std.os.AF_INET, std.os.SOCK_DGRAM, 0);
        errdefer std.os.close(sock);

        {
            var opt: c_int align(1) = 1;
            if (std.os.linux.setsockopt(sock, std.os.SOL_SOCKET, std.os.SO_REUSEADDR, @ptrCast([*]const u8, &opt), @sizeOf(c_int)) != 0)
                return error.SocketError;
            if (std.os.linux.setsockopt(sock, std.os.SOL_SOCKET, std.os.SO_BROADCAST, @ptrCast([*]const u8, &opt), @sizeOf(c_int)) != 0)
                return error.SocketError;
        }

        try std.os.bind(sock, &std.net.Address.initIp4(0, port_number).os_addr);

        std.debug.warn("sock = {}\n", sock);

        var con = Connection{
            .socket = sock,
            .localAddress = address,
            .allocator = _allocator,
            .packets = std.ArrayList(*Packet).init(_allocator),
            .mutex = std.Mutex.init(),
            .transmitQueue = LinkedList(Packet).init(),
            .receiveQueue = LinkedList(Packet).init(),
        };

        return con;
    }

    fn deinit(self: *Connection) void {
        for (self.packets.toSlice()) |p| {
            self.allocator.destroy(p);
        }
        self.packets.deinit();
        std.os.close(self.socket);
        if (self.thread) |thr| {
            thr.wait();
        }
    }

    fn start(self: *Connection) !void {
        if (self.thread == null) {
            self.thread = try std.Thread.spawn(self, receiverThreadWrapper);
        }
    }

    fn receiverThreadWrapper(self: *Connection) void {
        receiverThread(self) catch |err| {
            std.debug.warn("error: {}\n", @errorName(err));
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        };
    }

    fn receiverThread(self: *Connection) !void {
        var buf: [1024]u8 align(16) = undefined;
        while (@atomicLoad(usize, &self.active, .SeqCst) != 0) {
            var len = try std.os.read(self.socket, buf[0..]);

            if (len >= PacketHeader.size) {
                var hdr = @ptrCast(*PacketHeader, &buf);
                if (len == PacketHeader.size + hdr.len) {
                    var data = buf[PacketHeader.size .. PacketHeader.size + hdr.len];
                    var checksum = calculateChecksum(data);

                    if (checksum == hdr.checksum) {
                        if (!Address.eql(hdr.src, self.localAddress)) {
                            if (Address.eql(hdr.dst, self.localAddress) or Address.eql(hdr.dst, Address.broadcast)) {
                                if (hdr.flags.ack != 0) {
                                    // is system response and not actual data
                                    if (!Address.eql(hdr.dst, Address.broadcast)) {
                                        // we received an ACK, we should now check if we've sent a message with that
                                        // sequenceID
                                        var packet = blk: {
                                            var elem = self.transmitQueue.front;
                                            while (elem) |ptr| : (elem = ptr.next) {
                                                if (ptr.getHeader().sequence == hdr.sequence)
                                                    break :blk ptr;
                                            }
                                            break :blk null;
                                        };

                                        if (packet) |pkt| {
                                            if (Address.eql(pkt.getHeader().dst, hdr.src)) {
                                                std.debug.warn("received ACK for previously sent message.\n");
                                                self.transmitQueue.remove(pkt);
                                            } else {
                                                std.debug.warn("received invalid message: ACK by invalid sender.\n");
                                            }
                                        }
                                    } else {
                                        std.debug.warn("received invalid message: is ACK, but also to broadcast.\n");
                                    }
                                } else {
                                    // is data
                                    var packet = try self.getAvailablePacket();
                                    std.mem.copy(u8, packet.data[0..], buf[0..len]);

                                    self.receiveQueue.pushBack(packet);

                                    if (!Address.eql(hdr.dst, Address.broadcast) and hdr.flags.reliable != 0) {
                                        // packet is reliable, so send an ACK
                                        var response = try self.getAvailablePacket();

                                        response.getHeader().* = PacketHeader{
                                            .src = self.localAddress,
                                            .dst = hdr.src,
                                            .flags = PacketFlags{
                                                .reliable = 0,
                                                .ack = 1,
                                            },
                                            .len = 0,
                                            .sequence = hdr.sequence,
                                            .checksum = 0,
                                        };

                                        try self.sendPacket(response);
                                    }
                                }
                            } else {
                                std.debug.warn("filtering message received for other.\n");
                            }
                        } else {
                            std.debug.warn("filtering message received from self.\n");
                        }
                    } else {
                        std.debug.warn("received invalid datagram: checksum was {}, but expected {}!\n", checksum, hdr.checksum);
                    }
                } else {
                    std.debug.warn("received invalid datagram: actual length was {}, but expected {}!\n", len, PacketHeader.size + hdr.len);
                }
            } else {
                std.debug.warn("received short datagram {} bytes!\n", len);
            }

            std.time.sleep(100);
        }
    }

    pub fn receivePacket(self: *Connection) ?*Packet {
        return self.receiveQueue.popFront();
    }
};

pub fn main() anyerror!void {
    if (std.os.argv.len < 2) {
        std.debug.warn("Missing argument: local address\n");
        return;
    }

    var localAddress = try Address.parse(std.mem.toSlice(u8, std.os.argv[1]));

    std.debug.warn("local address = {}\n", localAddress);

    var con = try Connection.init(std.heap.direct_allocator, localAddress);
    defer con.deinit();

    try con.start();

    std.debug.warn("send '{x}'\n", "Hello, World");

    try con.send(null, "Hello, World", false);

    if (std.os.argv.len > 2) {
        var target = try Address.parse(std.mem.toSlice(u8, std.os.argv[2]));
        try con.send(target, "ACK mich!", true);
    }

    var stdin = try std.io.getStdIn();
    var stream = stdin.inStream();

    std.debug.warn("socket is now listening!\n");
    while (true) {
        // var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
        // defer arena.deinit();

        // var text = stream.stream.readUntilDelimiterAlloc(&arena.allocator, '\n', 1024) catch |err| switch (err) {
        //     error.EndOfStream => break,
        //     else => return err,
        // };
        // defer arena.allocator.free(text);

        // std.debug.warn("'{}'\n", text);
        while (con.receivePacket()) |packet| {
            std.debug.warn("received packet: {}\n{}\n", packet.getHeader(), packet.getPayload());

            packet.returnToPool();
        }

        std.time.sleep(100 * std.time.millisecond);
    }
}

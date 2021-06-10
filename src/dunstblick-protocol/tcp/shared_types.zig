const std = @import("std");

const CryptoState = @import("CryptoState.zig");

pub const State = union(enum) {
    initiate_handshake,
    acknowledge_handshake,
    authenticate_info,
    authenticate_result,
    connect_header,
    connect_response,
    connect_response_item: usize,
    resource_request,
    resource_header: usize,

    /// The connection was established successfully
    established,

    /// The connection handshake failed
    faulted,
};

pub const ConsumeResult = union(enum) {
    need_more,
    ok: Info,

    pub const Info = struct {
        consumed: usize,
        data: []u8,

        // pub fn get(self: @This(), comptime T: type) *align(1) T {
        //     std.debug.assert(self.data.len == @sizeOf(T));
        //     return std.mem.bytesAsValue(T, self.data[0..@sizeOf(T)]);
        // }
    };
};

pub const MsgReceiveBuffer = struct {
    const Self = @This();

    buffer: std.ArrayListAlignedUnmanaged(u8, 64) = .{},

    /// Pushes a portion of `new_data` to the buffer. The return value will either contain
    /// how many bytes of `new_data` were consumed or `need_more`, which tells you that all data
    /// was consumed.
    /// When `ok` is returned, the value will contain a buffer `.data` with the received bytes of `expected_len`.
    /// These bytes will be valid until the next call to `pushData` or `deinit`.
    pub fn pushData(self: *Self, allocator: *std.mem.Allocator, new_data: []const u8, expected_size: usize) error{OutOfMemory}!ConsumeResult {
        return pushDataGeneric(self, allocator, new_data, expected_size, true);
    }

    /// Similar to `pushData`, but allows to be called several times without resetting the
    /// stored data.
    pub fn pushPrefix(self: *Self, allocator: *std.mem.Allocator, new_data: []const u8, expected_size: usize) error{OutOfMemory}!ConsumeResult {
        return pushDataGeneric(self, allocator, new_data, expected_size, false);
    }

    pub fn pushDataGeneric(self: *Self, allocator: *std.mem.Allocator, new_data: []const u8, expected_size: usize, auto_reset: bool) error{OutOfMemory}!ConsumeResult {
        const old_len = self.buffer.items.len;

        if (old_len + new_data.len < expected_size) {
            // new_data does not contain enough data to fulfill our request, we consume the full slice
            // and append it:
            try self.buffer.appendSlice(allocator, new_data);
            return .need_more;
        }

        if (!auto_reset and old_len >= expected_size) {
            // we already collected enough data for a non-auto_reset event.
            // this is only allowed in the non-auto_reset path as
            // the auto-reset would reset itself as soon as it has old_len == expected_size
            return ConsumeResult{
                .ok = .{
                    .consumed = 0,
                    .data = self.buffer.items[0..expected_size],
                },
            };
        }

        // new_data has at least enough bytes to fulfill the request.
        // append the requested bits and ignore the rest.

        const rest = ((new_data.len + old_len) - expected_size);

        const consumed = new_data.len - rest;

        try self.buffer.appendSlice(allocator, new_data[0..consumed]);

        var result = ConsumeResult{
            .ok = .{
                .consumed = consumed,
                .data = self.buffer.items[0..expected_size],
            },
        };

        if (auto_reset) {
            // This is safe as shrinkRetainingCapacity won't invalidate or free
            // the bytes in `buffer.items`, it will just resize `buffer.items` to zero.
            self.buffer.shrinkRetainingCapacity(0);
        }

        return result;
    }

    pub fn deinit(self: *Self, allocator: *std.mem.Allocator) void {
        self.buffer.deinit(allocator);
    }
};

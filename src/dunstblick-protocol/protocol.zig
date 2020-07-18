pub const udp = @import("udp.zig");

pub const tcp = struct {
    pub usingnamespace v1;

    pub const v1 = @import("tcp/v1.zig");
};

pub usingnamespace @import("data-types.zig");

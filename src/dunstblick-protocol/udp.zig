pub const AnnouncementType = extern enum(u16) {
    discover = 0,
    respond_discover = 1,
    _,
};

/// magic byte sequence to recognize dunstblick messages
pub const magic = [4]u8{ 0x73, 0xe6, 0x37, 0x28 };

/// Shared header for every
pub const Header = extern struct {
    const Self = @This();

    magic: [4]u8 = magic,
    type: AnnouncementType,

    pub fn create(_type: AnnouncementType) Self {
        return Self{
            .type = _type,
        };
    }
};

/// Discovery request. If this message is received, a dunstblick client
/// responds with its service description (`DiscoverResponse`).
pub const Discover = extern struct {
    header: Header,
};

/// Response to a `Discover` message.
/// This message contains information on how to connect to the application.
pub const DiscoverResponse = extern struct {
    header: Header,
    tcp_port: u16,
    length: u16,
    name: [64]u8,
};

/// Message union that contains all possible messages.
/// Use `header` field to query which field is valid.
pub const Message = extern union {
    header: Header,
    discover: Discover,
    discover_response: DiscoverResponse,
};

comptime {
    const std = @import("std");
    std.debug.assert(@sizeOf(Header) == 6);
    std.debug.assert(@sizeOf(Discover) == 6);
    std.debug.assert(@sizeOf(DiscoverResponse) == 74);
}

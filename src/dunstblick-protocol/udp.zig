const std = @import("std");

pub const AnnouncementType = extern enum(u16) {
    discover = 0,
    respond_discover = 1,
    _,
};

/// magic byte sequence to recognize dunstblick messages
pub const magic = [4]u8{ 0x73, 0xe6, 0x37, 0x28 };

pub const port = 1309;
pub const multicast_group_v4 = [4]u8{ 224, 0, 0, 1 };

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
    pub const buffer_size = @sizeOf(@This()) + @sizeOf(ShortDescription) + @sizeOf(IconDescription);

    pub const Features = packed struct {
        /// A ShortDescription struct is present
        has_description: bool,

        /// A IconDescription struct is present
        has_icon: bool,

        /// If this is `true`, authentication is *required* to use this
        /// service.
        requires_auth: bool,

        /// If this is `true`, the user is requested to enter a user name.
        /// If authentication is optional, the user can skip this.
        wants_username: bool,

        /// If this is `true`, the user is requested to enter a password.
        /// If authentication is optional, the user can skip this.
        wants_password: bool,

        /// If this is `true`, the connection will be encrypted
        is_encrypted: bool,

        reserved: u9 = 0,
    };

    pub const ShortDescription = extern struct {
        pub const max_length = 256;

        text: [max_length]u8, // NUL-padded

        pub fn get(self: *const @This()) []const u8 {
            return std.mem.sliceTo(&self.text, 0);
        }

        pub fn set(self: *@This(), str: []const u8) !void {
            if (str.len > self.text.len)
                return error.InputTooLong;
            std.mem.set(u8, &self.text, 0);
            std.mem.copy(u8, &self.text, str);
        }
    };

    pub const IconDescription = extern struct {
        pub const max_length = 512;

        size: u16,
        data: [max_length]u8,

        pub fn get(self: *const @This()) []const u8 {
            return self.data[0..std.math.min(self.data.len, self.size)];
        }

        pub fn set(self: *@This(), data: []const u8) !void {
            if (data.len > self.data.len)
                return error.InputTooLong;
            self.size = @intCast(u16, data.len);
            std.mem.set(u8, &self.data, 0);
            std.mem.copy(u8, &self.data, data);
        }
    };

    comptime {
        if (@sizeOf(Features) != 2)
            @compileError("Features must be compatible to a 16 bit integer!");
    }

    header: Header = Header.create(.respond_discover),
    features: Features,
    tcp_port: u16,
    display_name: [64]u8, // NUL-padded

    pub fn setName(self: *@This(), str: []const u8) !void {
        if (str.len > self.display_name.len)
            return error.InputTooLong;
        std.mem.set(u8, &self.display_name, 0);
        std.mem.copy(u8, &self.display_name, str);
    }

    pub fn getName(self: @This()) []const u8 {
        return std.mem.sliceTo(&self.display_name, 0);
    }

    pub fn getTotalPacketLength(self: @This()) usize {
        var size: usize = @sizeOf(@This());
        if (self.features.has_description)
            size += @sizeOf(ShortDescription);
        if (self.features.has_icon)
            size += @sizeOf(IconDescription);
        return size;
    }

    // optional "fields" are in this order:
    // - ShortDescription
    // - IconDescription

    pub fn getDescriptionOffset(self: @This()) ?usize {
        return if (self.features.has_description)
            @sizeOf(@This())
        else
            null;
    }

    pub fn getIconOffset(self: @This()) ?usize {
        if (!self.features.has_icon)
            return null;
        var offset: usize = @sizeOf(@This());
        if (self.features.has_description)
            offset += @sizeOf(ShortDescription);
        return offset;
    }

    pub fn getDescriptionPtr(self: *@This()) ?*ShortDescription {
        return if (self.getDescriptionOffset()) |offset|
            @ptrCast(*ShortDescription, @alignCast(@alignOf(ShortDescription), @ptrCast([*]u8, self) + offset))
        else
            null;
    }

    pub fn getIconPtr(self: *@This()) ?*IconDescription {
        return if (self.getIconOffset()) |offset|
            @ptrCast(*IconDescription, @alignCast(@alignOf(IconDescription), @ptrCast([*]u8, self) + offset))
        else
            null;
    }
};

/// Message union that contains all possible messages.
/// Use `header` field to query which field is valid.
pub const Message = extern union {
    header: Header,
    discover: Discover,
    discover_response: DiscoverResponse,
    max_buffer: [DiscoverResponse.buffer_size]u8,
};

comptime {
    std.debug.assert(@sizeOf(Header) == 6);
    std.debug.assert(@sizeOf(Discover) == 6);
    std.debug.assert(@sizeOf(DiscoverResponse) == 74);
}

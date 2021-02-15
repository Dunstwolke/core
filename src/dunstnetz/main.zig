const std = @import("std");
const network = @import("network");

pub const DeviceAddress = enum(u48) {
    const Self = @This();

    pub fn fromBytes(value: [6]u8) Self {
        return @bitCast(Self, value);
    }

    pub fn toBytes(self: Self) [6]u8 {
        return @bitCast([6]u8, self);
    }
};

pub const AppAddress = enum(u24) {
    const Self = @This();

    pub fn fromBytes(value: [3]u8) Self {
        return @bitCast(Self, value);
    }

    pub fn toBytes(self: Self) [3]u8 {
        return @bitCast([3]u8, self);
    }
};

/// The broadcast address. Can be used to
pub const broadcast = DeviceAddress.fromBytes([6]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF });

pub const DeviceConfig = struct {
    name: []const u8,
    address: DeviceAddress,
    capabilities: DeviceCaps,
};

pub const DeviceCaps = struct {
    audio_sink: bool,
    audio_source: bool,
    mass_storage: bool,
    display: bool,
    app_host: bool,
};

pub fn init() !void {
    try network.init();
}

pub fn deinit() void {
    network.deinit();
}

pub const Device = struct {
    const Self = @This();

    pub fn create(device_config: DeviceConfig) !Self {
        return Self{};
    }

    pub fn destroy(self: *Self) void {
        self.* = undefined;
    }

    pub fn update(self: *Self) void {
        unreachable;
    }
};

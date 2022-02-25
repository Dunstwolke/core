const std = @import("std");
const rpc = @import("antiphony");
const network = @import("network");

pub const dunstfabric_port = 8938;
pub const protocol_magic = [4]u8{ 0xf7, 0xcb, 0xbb, 0x05 };
pub const protocol_version: u8 = 1;

pub const end_point = network.EndPoint{
    .address = .{ .ipv4 = network.Address.IPv4.loopback },
    .port = dunstfabric_port,
};

pub const public_end_point = network.EndPoint{
    .address = .{ .ipv4 = network.Address.IPv4.any },
    .port = dunstfabric_port,
};

pub const ProcessID = union(enum) {
    windows: std.os.windows.DWORD,
    unix: i32,
};

pub const ServiceControlError = error{ Timeout, UnkownService, IoError, FileNotFound, OutOfMemory };
pub const CreateServiceError = error{ Timeout, AlreadyExists, FileNotFound, OutOfMemory };

pub const ServiceStatus = struct {
    online: bool,
    pid: ?ProcessID,
};

pub const ServiceDescriptor = struct {
    autostart: bool = false,
    restart: Restart = .no,
    command: []const []const u8,
};

pub const Restart = enum {
    /// The service will never be restarted.
    no,

    /// The service will only be restarted if the exit code is not 0.
    @"on-failure",

    /// The service will always be restarted unless it is explicitly stopped.
    always,
};

pub const Definition = rpc.CreateDefinition(.{
    .host = .{
        // Service control
        .startService = fn (service: []const u8) ServiceControlError!void,
        .restartService = fn (service: []const u8) ServiceControlError!void,
        .stopService = fn (service: []const u8) ServiceControlError!void,
        .getServiceStatus = fn (service: []const u8) ServiceControlError!ServiceStatus,

        // Service management
        .createService = fn (name: []const u8, desc: ServiceDescriptor) CreateServiceError!void,
        .deleteService = fn (name: []const u8) ServiceControlError!void,
        .getServiceDescriptor = fn (name: []const u8) CreateServiceError!ServiceDescriptor,
    },
    .client = .{},
});

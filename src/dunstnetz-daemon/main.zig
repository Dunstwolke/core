const std = @import("std");
const dunstnetz = @import("dunstnetz");
const wasm = @import("wasm");

const device_config = dunstnetz.DeviceConfig{
    .name = "Demo Device",
    .address = dunstnetz.DeviceAddress.fromBytes([6]u8{ 0xae, 0x22, 0x3a, 0xa1, 0x0c, 0x68 }),
    .capabilities = dunstnetz.DeviceCaps{
        .audio_sink = false,
        .audio_source = false,
        .mass_storage = false,
        .display = false,
        .app_host = false,
        .internet_access = false,
    },
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    defer _ = gpa.deinit();

    try dunstnetz.init();
    defer dunstnetz.deinit();

    var file = try std.fs.cwd().openFile("wasm-demo.wasm", .{});
    defer file.close();

    var module = try wasm.Module.parse(&gpa.allocator, file.reader());
    defer module.deinit();

    var instance = try module.instantiate(&gpa.allocator, null, struct {});
    defer instance.deinit();

    {
        const result = try instance.call("app_init", .{@as(i32, 1)});
        std.debug.print("{}\n", .{result});
    }
    {
        const result = try instance.call("app_init", .{@as(i32, 0)});
        std.debug.print("{}\n", .{result});
    }

    // var device = try dunstnetz.Device.create(device_config);
    // defer device.destroy();

    // try device.send(dunstnetz.Message{
    //     .receiver = dunstnetz.DeviceAddress.fromBytes([6]u8{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }),
    //     .data = "Hello, World!",
    //     .reliable = true,
    //     .sequenced = undefined, // ignored for
    //     .channel = 0, // 0 … 63
    // });

    // var session = try device.openSession(
    //     dunstnetz.AppAddress.init(0x00, 0x00, 0x01), // target application
    //     &[_]dunstnetz.ChannelConfig{ // init 4 channels, each one has
    //         .{ .reliable = false, .sequenced = false },
    //         .{ .reliable = false, .sequenced = true },
    //         .{ .reliable = true, .sequenced = false },
    //         .{ .reliable = true, .sequenced = true },
    //     },
    // );
    // defer session.close();

    while (true) {
        // try device.update();
    }
}

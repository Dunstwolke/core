const std = @import("std");

export fn app_init(value: i32) i32 {
    return value;
}

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace) noreturn {
    while (true) {}
}

pub fn main() void {
    std.mem.doNotOptimizeAway(app_init);
}

// zig build-exe -target wasm32-freestanding-none -O ReleaseSmall -fno-compiler-rt src/apps/wasm-demo.zig  && wasm2wat wasm-demo.wasm > wasm-demo.wat

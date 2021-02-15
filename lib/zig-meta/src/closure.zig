const std = @import("std");

// pub fn main() void {
//     std.log.info("mutable closure:", .{});
//     runMutDemo();

//     std.log.info("const closure:", .{});
//     runConstDemo();
// }

// fn runMutDemo() void {
//     var call_count: usize = 0;

//     var closed = Closure(struct {
//         fn C(state: *struct { i: u32 = 0, c: *usize }, increment: u32) u32 {
//             defer state.i += increment;
//             state.c.* += 1;
//             return state.i;
//         }
//     }.C).init(
//         .{ .c = &call_count },
//     );

//     std.log.info("  invocation 1 => {}", .{closed.invoke(.{1})});
//     std.log.info("  invocation 2 => {}", .{closed.invoke(.{0})});
//     std.log.info("  invocation 3 => {}", .{closed.invoke(.{2})});
//     std.log.info("  invocation 4 => {}", .{closed.invoke(.{3})});
//     std.log.info("  invocation 5 => {}", .{closed.invoke(.{0})});

//     std.log.info("  invocation count: {}", .{call_count});
// }

// fn runConstDemo() void {
//     const closed = Closure(struct {
//         fn C(state: struct { i: u32 }, increment: u32) u32 {
//             return state.i + increment;
//         }
//     }.C).init(
//         .{ .i = 10 },
//     );

//     std.log.info("  static invocation 1 => {}", .{closed.invoke(.{1})});
//     std.log.info("  static invocation 2 => {}", .{closed.invoke(.{0})});
//     std.log.info("  static invocation 3 => {}", .{closed.invoke(.{2})});
//     std.log.info("  static invocation 4 => {}", .{closed.invoke(.{3})});
//     std.log.info("  static invocation 5 => {}", .{closed.invoke(.{0})});
// }

/// Creates a closure type that will store and pass the first argument of the passed
/// function
pub fn Closure(comptime function: anytype) type {
    const F = @TypeOf(function);
    const A0 = @typeInfo(F).Fn.args[0].arg_type.?;

    return struct {
        const Self = @This();

        pub const is_mutable = (@typeInfo(A0) == .Pointer);
        pub const State = if (is_mutable)
            std.meta.Child(A0)
        else
            A0;
        pub const Result = (@typeInfo(F).Fn.return_type.?);

        state: State,

        pub fn init(state: State) Self {
            return Self{ .state = state };
        }

        pub fn invoke(self: if (is_mutable) *Self else Self, args: anytype) Result {
            return @call(.{}, function, .{if (is_mutable) &self.state else self.state} ++ args);
        }
    };
}

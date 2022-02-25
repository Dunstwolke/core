const std = @import("std");

// const WriterSpec = struct {
//     pub const write = fn (self: *@This(), msg: []const u8) error{IoError}!void;

//     pub const flush = fn (self: @This()) void;
// };

// const Writer = Interface(WriterSpec);

// const LogWriter = struct {
//     pub fn write(self: *@This(), msg: []const u8) error{IoError}!void {
//         std.log.info("LogWriter.write(msg: {s})", .{msg});
//     }

//     pub fn flush(self: @This()) void {
//         std.log.info("LogWriter.flush()", .{});
//     }
// };

// fn invokeWriter(writer: Writer) !void {
//     // this can be replaced with an improved version when @Type(.Struct) allows declarations:
//     // try writer.write("hello");
//     // writer.flush();
//     try writer.invoke("write", .{"hello"});
//     writer.invoke("flush", .{});
// }

// pub fn main() !void {
//     var log_writer = LogWriter{};

//     try invokeWriter(interfaceCast(Writer, &log_writer));
// }

pub fn interfaceCast(comptime InterfaceType: type, pointer: anytype) InterfaceType {
    return InterfaceType{
        .vtable = InterfaceType.getVTable(@TypeOf(pointer.*)),
        .instance = @ptrCast(*InterfaceType.ErasedSelf, pointer),
    };
}

pub fn Interface(comptime Spec: type) type {
    const decls = @typeInfo(Spec).Struct.decls;

    return struct {
        const Self = @This();
        const ErasedSelf = struct {};

        fn replaceSelfType(comptime src_type: type) type {
            if (src_type == Spec)
                return *const ErasedSelf;
            const info = @typeInfo(src_type);
            return switch (info) {
                .Pointer => |ptr| {
                    var clone = ptr;
                    if (clone.child == Spec)
                        clone.child = ErasedSelf;
                    return @Type(.{ .Pointer = clone });
                },
                else => @compileError(@typeName(src_type) ++ " is not translatable!"),
            };
        }

        const VTable = blk: {
            const dummy_field = std.builtin.TypeInfo.StructField{
                .name = "",
                .field_type = void,
                .default_value = {},
                .is_comptime = true,
                .alignment = 0,
            };
            var fields = [1]std.builtin.TypeInfo.StructField{dummy_field} ** decls.len;
            for (fields) |*field, i| {
                const srcFn = @typeInfo(decls[i].data.Type).Fn;

                // create copy of the argument list
                var args = srcFn.args[0..srcFn.args.len].*;

                args[0].arg_type = if (args[0].arg_type) |arg_type|
                    replaceSelfType(arg_type)
                else
                    null;

                var dstFn = srcFn;
                dstFn.args = &args;

                const F = @Type(.{ .Fn = dstFn });

                field.* = std.builtin.TypeInfo.StructField{
                    .name = decls[i].name,
                    .field_type = F,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(F),
                };
            }

            const struct_def = std.builtin.TypeInfo.Struct{
                .layout = .Auto,
                .fields = &fields,
                .decls = &[_]std.builtin.TypeInfo.Declaration{},
                .is_tuple = false,
            };

            const struct_info = std.builtin.TypeInfo{
                .Struct = struct_def,
            };

            break :blk @Type(struct_info);
        };

        pub fn getWrapper(comptime T: type, comptime field_name: []const u8, comptime field_type: type) field_type {
            const field_info = @typeInfo(@TypeOf(@field(T, field_name))).Fn;
            const F = struct {
                fn invoke(erased_self: anytype, args: anytype) field_info.return_type.? {
                    const A0 = field_info.args[0].arg_type.?;

                    var self = if (A0 == T)
                        @ptrCast(*const T, erased_self).*
                    else if (A0 == *T)
                        @ptrCast(*T, erased_self)
                    else if (A0 == *const T)
                        @ptrCast(*const T, erased_self)
                    else
                        @compileError("unsupported self type " ++ @typeName(A0));

                    return @call(
                        .{},
                        @field(T, field_name),
                        .{self} ++ args,
                    );
                }
            };
            return comptime createCallWrapper(field_type, F.invoke);
        }

        pub fn getVTable(comptime T: type) *const VTable {
            comptime var table: VTable = undefined;

            inline for (std.meta.fields(VTable)) |fld| {
                @field(table, fld.name) = comptime getWrapper(T, fld.name, fld.field_type);
            }

            const Storage = struct {
                const vtable: VTable = table;
            };
            return &Storage.vtable;
        }

        vtable: *const VTable,
        instance: *ErasedSelf,

        pub fn invoke(self: @This(), comptime function: []const u8, args: anytype) @typeInfo(@field(Spec, function)).Fn.return_type.? {
            return @call(
                .{},
                @field(self.vtable, function),
                .{self.instance} ++ args,
            );
        }
    };
}

fn createCallWrapper(comptime FunctionType: type, comptime function: anytype) FunctionType {
    const fn_info = @typeInfo(FunctionType).Fn;
    const fn_args = fn_info.args;
    const R = fn_info.return_type orelse @compileError("Function must be non-generic");

    comptime var A: [fn_args.len]type = undefined;
    inline for (A) |*t, i| {
        t.* = fn_args[i].arg_type orelse @compileError("Function must be non-generic");
    }

    const Wrappers = struct {
        fn fn1(a0: A[0]) R {
            return function(a0, .{});
        }
        fn fn2(a0: A[0], a1: A[1]) R {
            return function(a0, .{a1});
        }
        fn fn3(a0: A[0], a1: A[1], a2: A[2]) R {
            return function(a0, .{ a1, a2 });
        }
        fn fn4(a0: A[0], a1: A[1], a2: A[2], a3: A[3]) R {
            return function(a0, .{ a1, a2, a3 });
        }
        fn fn5(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4]) R {
            return function(a0, .{ a1, a2, a3, a4 });
        }
        fn fn6(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5]) R {
            return function(a0, .{ a1, a2, a3, a4, a5 });
        }
        fn fn7(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6 });
        }
        fn fn8(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7 });
        }
        fn fn9(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7, a8 });
        }
        fn fn10(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7, a8, a9 });
        }
        fn fn11(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 });
        }
        fn fn12(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 });
        }
        fn fn13(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11], a12: A[12]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 });
        }
        fn fn14(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11], a12: A[12], a13: A[13]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13 });
        }
        fn fn15(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11], a12: A[12], a13: A[13], a14: A[14]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 });
        }
        fn fn16(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11], a12: A[12], a13: A[13], a14: A[14], a15: A[15]) R {
            return function(a0, .{ a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15 });
        }
    };

    return switch (fn_args.len) {
        1 => Wrappers.fn1,
        2 => Wrappers.fn2,
        3 => Wrappers.fn3,
        4 => Wrappers.fn4,
        5 => Wrappers.fn5,
        6 => Wrappers.fn6,
        7 => Wrappers.fn7,
        8 => Wrappers.fn8,
        9 => Wrappers.fn9,
        10 => Wrappers.fn10,
        11 => Wrappers.fn11,
        12 => Wrappers.fn12,
        13 => Wrappers.fn13,
        14 => Wrappers.fn14,
        15 => Wrappers.fn15,
        16 => Wrappers.fn16,
        else => @compileError("Unsupported number of arguments!"),
    };
}

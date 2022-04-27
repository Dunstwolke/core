const std = @import("std");
const logger = std.log.scoped(.libmagic);

pub const MagicSet = opaque {
    pub const open = magic_open;
    pub const close = magic_close;
    pub const getPath = magic_getpath;
    pub const file = magic_file;
    pub const descriptor = magic_descriptor;
    pub const buffer = magic_buffer;
    pub fn getError(set: *MagicSet) ?[:0]const u8 {
        return if (magic_error(set)) |err|
            std.mem.span(err)
        else
            null;
    }
    pub const getFlags = magic_getflags;
    pub const setFlags = magic_setflags;
    pub const version = magic_version;
    pub const load = magic_load;
    pub const loadBuffers = magic_load_buffers;
    pub const compile = magic_compile;
    pub const check = magic_check;
    pub const list = magic_list;
    pub const errno = magic_errno;
    pub const setParam = magic_setparam;
    pub const getParam = magic_getparam;

    pub fn openBuiltin() !*MagicSet {
        const magic = MagicSet.open(MIME_TYPE) orelse {
            logger.err("Cannot create magic database!", .{});
            return error.MagicError;
        };
        errdefer magic.close();

        logger.info("Load magic database...", .{});

        const magic_data_set: []const u8 = @embedFile("../../vendor/file-5.40/magic/magic.mgc");
        const magic_data_sets_ptrs = [_]*const anyopaque{magic_data_set.ptr};
        const magic_data_sets_lens = [_]usize{magic_data_set.len};

        if (magic.loadBuffers(&magic_data_sets_ptrs, &magic_data_sets_lens, 1) == -1) {
            logger.err("{s}", .{magic.getError()});
            return error.MagicError;
        }

        if (magic.getError()) |err| {
            logger.warn("{s}", .{std.mem.span(err)});
            return error.MagicError;
        }

        return magic;
    }
};

extern fn magic_open(c_int) ?*MagicSet;
extern fn magic_close(*MagicSet) void;
extern fn magic_getpath(?[*:0]const u8, c_int) ?[*:0]const u8;
extern fn magic_file(*MagicSet, [*:0]const u8) ?[*:0]const u8;
extern fn magic_descriptor(*MagicSet, c_int) ?[*:0]const u8;
extern fn magic_buffer(*MagicSet, ?*const anyopaque, usize) ?[*:0]const u8;
extern fn magic_error(*MagicSet) ?[*:0]const u8;
extern fn magic_getflags(*MagicSet) c_int;
extern fn magic_setflags(*MagicSet, c_int) c_int;
extern fn magic_version() c_int;
extern fn magic_load(*MagicSet, [*:0]const u8) c_int;
extern fn magic_load_buffers(*MagicSet, [*]const *const anyopaque, [*]const usize, usize) c_int;
extern fn magic_compile(*MagicSet, [*:0]const u8) c_int;
extern fn magic_check(*MagicSet, [*:0]const u8) c_int;
extern fn magic_list(*MagicSet, [*:0]const u8) c_int;
extern fn magic_errno(*MagicSet) c_int;
extern fn magic_setparam(*MagicSet, Parameter, ?*const anyopaque) c_int;
extern fn magic_getparam(*MagicSet, Parameter, ?*anyopaque) c_int;

pub const Parameter = enum(c_int) {
    indir_max = PARAM_INDIR_MAX,
    name_max = PARAM_NAME_MAX,
    elf_phnum_max = PARAM_ELF_PHNUM_MAX,
    elf_shnum_max = PARAM_ELF_SHNUM_MAX,
    elf_notes_max = PARAM_ELF_NOTES_MAX,
    regex_max = PARAM_REGEX_MAX,
    bytes_max = PARAM_BYTES_MAX,
    encoding_max = PARAM_ENCODING_MAX,
};

pub const NONE = @as(c_int, 0x0000000);
pub const DEBUG = @as(c_int, 0x0000001);
pub const SYMLINK = @as(c_int, 0x0000002);
pub const COMPRESS = @as(c_int, 0x0000004);
pub const DEVICES = @as(c_int, 0x0000008);
pub const MIME_TYPE = @as(c_int, 0x0000010);
pub const CONTINUE = @as(c_int, 0x0000020);
pub const CHECK = @as(c_int, 0x0000040);
pub const PRESERVE_ATIME = @as(c_int, 0x0000080);
pub const RAW = @as(c_int, 0x0000100);
pub const ERROR = @as(c_int, 0x0000200);
pub const MIME_ENCODING = @as(c_int, 0x0000400);
pub const MIME = MIME_TYPE | MIME_ENCODING;
pub const APPLE = @as(c_int, 0x0000800);
pub const EXTENSION = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000000, .hexadecimal);
pub const COMPRESS_TRANSP = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x2000000, .hexadecimal);
pub const NODESC = EXTENSION | MIME | APPLE;
pub const NO_CHECK_COMPRESS = @as(c_int, 0x0001000);
pub const NO_CHECK_TAR = @as(c_int, 0x0002000);
pub const NO_CHECK_SOFT = @as(c_int, 0x0004000);
pub const NO_CHECK_APPTYPE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0008000, .hexadecimal);
pub const NO_CHECK_ELF = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0010000, .hexadecimal);
pub const NO_CHECK_TEXT = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0020000, .hexadecimal);
pub const NO_CHECK_CDF = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0040000, .hexadecimal);
pub const NO_CHECK_CSV = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0080000, .hexadecimal);
pub const NO_CHECK_TOKENS = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0100000, .hexadecimal);
pub const NO_CHECK_ENCODING = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0200000, .hexadecimal);
pub const NO_CHECK_JSON = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0400000, .hexadecimal);
//pub const NO_CHECK_BUILTIN = (((((((((MAGIC_NO_CHECK_COMPRESS | MAGIC_NO_CHECK_TAR) | MAGIC_NO_CHECK_APPTYPE) | MAGIC_NO_CHECK_ELF) | MAGIC_NO_CHECK_TEXT) | MAGIC_NO_CHECK_CSV) | MAGIC_NO_CHECK_CDF) | MAGIC_NO_CHECK_TOKENS) | MAGIC_NO_CHECK_ENCODING) | MAGIC_NO_CHECK_JSON) | @as(c_int, 0);
//pub const NO_CHECK_ASCII = MAGIC_NO_CHECK_TEXT;
pub const NO_CHECK_FORTRAN = @as(c_int, 0x000000);
pub const NO_CHECK_TROFF = @as(c_int, 0x000000);
pub const VERSION = 5.40;
pub const PARAM_INDIR_MAX = @as(c_int, 0);
pub const PARAM_NAME_MAX = @as(c_int, 1);
pub const PARAM_ELF_PHNUM_MAX = @as(c_int, 2);
pub const PARAM_ELF_SHNUM_MAX = @as(c_int, 3);
pub const PARAM_ELF_NOTES_MAX = @as(c_int, 4);
pub const PARAM_REGEX_MAX = @as(c_int, 5);
pub const PARAM_BYTES_MAX = @as(c_int, 6);
pub const PARAM_ENCODING_MAX = @as(c_int, 7);

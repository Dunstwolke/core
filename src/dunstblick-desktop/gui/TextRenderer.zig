const std = @import("std");

const c = @cImport({
    @cInclude("stb_truetype.h");
});

const Framebuffer = @import("Framebuffer.zig");
const Color = Framebuffer.Color;
const Size = @import("Size.zig");

const Self = @This();

font: c.stbtt_fontinfo,
allocator: *std.mem.Allocator,
arena: std.heap.ArenaAllocator,
glyphs: std.AutoHashMap(u24, Glyph),

font_size: u15,

ascent: i16,
descent: i16,
line_gap: i16,

/// Scale of `advance_width` and `left_side_bearing`
scale: f32,

pub fn init(allocator: *std.mem.Allocator, ttf: []const u8, font_size: u15) !Self {
    var info: c.stbtt_fontinfo = undefined;

    const offset = c.stbtt_GetFontOffsetForIndex(ttf.ptr, 0);
    if (c.stbtt_InitFont(&info, ttf.ptr, offset) == 0)
        return error.TtfFailure;

    var ascent: c_int = undefined;
    var descent: c_int = undefined;
    var line_gap: c_int = undefined;
    c.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);

    return Self{
        .font = info,
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .glyphs = std.AutoHashMap(u24, Glyph).init(allocator),
        .font_size = font_size,
        .ascent = @intCast(i16, ascent),
        .descent = @intCast(i16, descent),
        .line_gap = @intCast(i16, line_gap),
        .scale = c.stbtt_ScaleForPixelHeight(&info, @intToFloat(f32, font_size)),
    };
}

pub fn deinit(self: *Self) void {
    self.glyphs.deinit();
    self.arena.deinit();
    self.* = undefined;
}

pub fn getGlyph(self: *Self, codepoint: u24) !Glyph {
    var gop = try self.glyphs.getOrPut(codepoint);
    if (!gop.found_existing) {
        var ix0: c_int = undefined;
        var iy0: c_int = undefined;
        var ix1: c_int = undefined;
        var iy1: c_int = undefined;

        c.stbtt_GetCodepointBitmapBox(
            &self.font,
            codepoint,
            self.scale,
            self.scale,
            &ix0,
            &iy0,
            &ix1,
            &iy1,
        );
        std.debug.assert(ix0 <= ix1);
        std.debug.assert(iy0 <= iy1);

        const width: u15 = @intCast(u15, ix1 - ix0);
        const height: u15 = @intCast(u15, iy1 - iy0);

        const bitmap = try self.arena.allocator.alloc(u8, width * height);
        errdefer self.arena.allocator.free(bitmap);

        c.stbtt_MakeCodepointBitmap(
            &self.font,
            bitmap.ptr,
            @intCast(c_int, width),
            @intCast(c_int, height),
            @intCast(c_int, width), // stride
            self.scale,
            self.scale,
            codepoint,
        );

        var advance_width: c_int = undefined;
        var left_side_bearing: c_int = undefined;
        c.stbtt_GetCodepointHMetrics(&self.font, codepoint, &advance_width, &left_side_bearing);

        // std.debug.print("{d} ({},{}) ({},{}) {}×{} {} {}\n", .{
        //     scale,
        //     ix0,
        //     iy0,
        //     ix1,
        //     iy1,
        //     width,
        //     height,
        //     advance_width,
        //     left_side_bearing,
        // });

        var glyph = Glyph{
            .pixels = bitmap,
            .width = width,
            .height = height,
            .advance_width = @intCast(i16, advance_width),
            .left_side_bearing = @intCast(i16, left_side_bearing),
            .offset_y = @intCast(i16, iy0),
        };

        gop.entry.value = glyph;
    }
    return gop.entry.value;
}

fn scaleInt(ival: isize, scale: f32) i16 {
    return @intCast(i16, @floatToInt(isize, std.math.round(@intToFloat(f32, ival) * scale)));
}

pub fn measureString(self: *Self, text: []const u8) Size {
    var utf8 = std.unicode.Utf8Iterator{
        .bytes = text,
        .i = 0,
    };

    var dx: i16 = 0;
    var dy: i16 = scaleInt(self.ascent, self.scale);

    var max_dx: i16 = 0;

    var previous_codepoint: ?u24 = null;
    while (utf8.nextCodepoint()) |codepoint| {
        if (codepoint == '\n') {
            dx = 0;
            dy += scaleInt(self.ascent - self.descent + self.line_gap, self.scale);
            previous_codepoint = null;
            continue;
        }

        const glyph = self.getGlyph(codepoint) catch continue;

        if (previous_codepoint) |prev| {
            dx += @intCast(i16, c.stbtt_GetCodepointKernAdvance(&self.font, prev, codepoint));
        }
        previous_codepoint = codepoint;

        max_dx = std.math.max(max_dx, scaleInt(dx + glyph.left_side_bearing, self.scale) + @intCast(i16, glyph.width));

        dx += glyph.advance_width;
    }
    dy += scaleInt(-self.descent + self.line_gap, self.scale);

    return Size{
        .width = @intCast(u15, max_dx),
        .height = @intCast(u15, dy),
    };
}

pub fn drawString(self: *Self, target_buffer: Framebuffer, text: []const u8, x: i16, y: i16, color: Color) void {
    var utf8 = std.unicode.Utf8Iterator{
        .bytes = text,
        .i = 0,
    };

    var dx: i16 = 0;
    var dy: i16 = scaleInt(self.ascent, self.scale);

    var previous_codepoint: ?u24 = null;
    while (utf8.nextCodepoint()) |codepoint| {
        if (codepoint == '\n') {
            dx = 0;
            dy += scaleInt(self.ascent - self.descent + self.line_gap, self.scale);
            previous_codepoint = null;
            continue;
        }

        const glyph = self.getGlyph(codepoint) catch continue;

        if (previous_codepoint) |prev| {
            dx += @intCast(i16, c.stbtt_GetCodepointKernAdvance(&self.font, prev, codepoint));
        }
        previous_codepoint = codepoint;

        {
            const off_x = x + scaleInt(dx + glyph.left_side_bearing, self.scale);
            const off_y = y + glyph.offset_y + dy;

            var py: u15 = 0;
            while (py < glyph.height) : (py += 1) {
                var px: u15 = 0;
                while (px < glyph.width) : (px += 1) {
                    const alpha = glyph.getAlpha(px, py);

                    const pixel = &target_buffer.scanline(@intCast(usize, off_y) + py)[@intCast(usize, off_x) + px];
                    const dest = pixel.*;
                    const source = Color{
                        .r = color.r,
                        .g = color.g,
                        .b = color.b,
                        .a = alpha,
                    };
                    pixel.* = Color.alphaBlend(dest, source, source.a);
                }
            }
        }

        // canvas.copyRectangle(
        //     x + scaleInt(dx + glyph.left_side_bearing, font_cache.scale),
        //     y + glyph.offset_y + dy,
        //     0,
        //     0,
        //     glyph.width,
        //     glyph.height,
        //     false,
        //     glyph,
        //     Glyph.getPixel,
        // );

        dx += glyph.advance_width;
    }
}

// get the bbox of the bitmap centered around the glyph origin; so the
// bitmap width is ix1-ix0, height is iy1-iy0, and location to place
// the bitmap top left is (leftSideBearing*scale,iy0).
// (Note that the bitmap uses y-increases-down, but the shape uses
// y-increases-up, so CodepointBitmapBox and CodepointBox are inverted.)

pub const Glyph = struct {
    const Self = @This();

    /// row-major grayscale pixels of the target map
    pixels: []u8,

    /// width of the image in pixels
    width: u15,

    /// height of the image in pixels
    height: u15,

    /// offset to the base line
    offset_y: i16,

    /// advanceWidth is the offset from the current horizontal position to the next horizontal position
    /// these are expressed in unscaled coordinates
    advance_width: i16,

    /// leftSideBearing is the offset from the current horizontal position to the left edge of the character
    left_side_bearing: i16,

    fn getAlpha(self: Glyph, x: u15, y: u15) u8 {
        if (x >= self.width or y >= self.height)
            return 0;

        return self.pixels[@as(usize, std.math.absCast(y)) * self.width + @as(usize, std.math.absCast(x))];
    }
};

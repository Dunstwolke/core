const painterz = @import("painterz");
const std = @import("std");
const sdl = @import("sdl2");

const c = @import("c.zig");

usingnamespace @import("types.zig");

pub const Color = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 0xFF,
};

pub const ColorScheme = struct {
    highlight: Color = Color{ .r = 0x00, .g = 0x00, .b = 0x80 },
    background: Color = Color{ .r = 0xd6, .g = 0xd3, .b = 0xce },
    input_field: Color = Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF },
    checker: Color = Color{ .r = 0xec, .g = 0xeb, .b = 0xe9 },
    bright_3d: Color = Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF },
    medium_3d: Color = Color{ .r = 0x84, .g = 0x82, .b = 0x84 },
    dark_3d: Color = Color{ .r = 0x42, .g = 0x41, .b = 0x42 },
    black_3d: Color = Color{ .r = 0x00, .g = 0x00, .b = 0x00 },
};

pub const Bevel = enum {
    /// A small border with a 3D effect, looks like a welding around the object
    edge,
    /// A small border with a 3D effect, looks like a crease around the object
    crease,
    /// A small border with a 3D effect, looks like the object is raised up from the surroundings
    raised,
    /// A small border with a 3D effect, looks like the object is sunken into the surroundings
    sunken,
    /// The *deep* 3D border
    input_field,
    /// Normal button outline
    button_default,
    /// Pressed button outline
    button_pressed,
    /// Active button outline, not pressed
    button_active,
};

pub const LineStyle = enum {
    /// A small border with a 3D effect, looks like a groove around the object
    crease,
    /// A small border with a 3D effect, looks like a welding around the object
    edge,
};

pub const WidgetColor = enum {
    background,
    input_field,
    highlight,
    checkered,
};

pub const Font = enum {
    sans,
    serif,
    monospace,
};

pub const TextAlign = enum {
    left,
    center,
    right,
    block,
};

pub const Painter = struct {
    const Self = @This();
    const Canvas = painterz.Canvas(*Self, Color, setPixel);

    size: sdl.Size,
    pixels: *sdl.Texture.PixelData,
    scheme: ColorScheme,

    fn setPixel(self: *Self, x: isize, y: isize, color: Color) void {
        if (x < 0 or y < 0) return;
        if (x >= self.size.width or y >= self.size.height) return;

        const pxl = &self.pixels.scanline(std.math.absCast(y), Color)[std.math.absCast(x)];

        if (color.a == 0) {
            return;
        } else if (color.a == 0xFF) {
            pxl.* = color;
        } else {
            const a = @intCast(u32, color.a);
            pxl.r = @intCast(u8, (@intCast(u32, pxl.r) * (255 - a) + a * @intCast(u32, color.r)) / 255);
            pxl.g = @intCast(u8, (@intCast(u32, pxl.b) * (255 - a) + a * @intCast(u32, color.g)) / 255);
            pxl.b = @intCast(u8, (@intCast(u32, pxl.g) * (255 - a) + a * @intCast(u32, color.b)) / 255);
        }
    }

    pub fn fill(self: *Self, color: Color) void {
        var y: usize = 0;
        while (y < self.size.height) : (y += 1) {
            var x: usize = 0;
            while (x < self.size.width) : (x += 1) {
                self.pixels.scanline(y, Color)[x] = color;
            }
        }
    }

    pub fn fillRectangle(self: *Self, rectangle: Rectangle, color: WidgetColor) void {
        var canvas = Canvas.init(self);
        switch (color) {
            .highlight => canvas.fillRectangle(rectangle.x, rectangle.y, rectangle.width, rectangle.height, self.scheme.highlight),
            .background => canvas.fillRectangle(rectangle.x, rectangle.y, rectangle.width, rectangle.height, self.scheme.background),
            .input_field => canvas.fillRectangle(rectangle.x, rectangle.y, rectangle.width, rectangle.height, self.scheme.input_field),
            .checkered => canvas.copyRectangle(rectangle.x, rectangle.y, 0, 0, rectangle.width, rectangle.height, {}, struct {
                fn pattern(src: void, x: isize, y: isize) Color {
                    return if ((x & 1) == (y & 1))
                        Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xFF }
                    else
                        Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF, .a = 0xFF };
                }
            }.pattern),
        }
    }

    pub fn drawRectangleImpl(canvas: *Canvas, rectangle: Rectangle, top_left: Color, bottom_right: Color) void {
        const l = rectangle.x;
        const t = rectangle.y;
        const r = rectangle.x + @intCast(isize, rectangle.width) - 1;
        const b = rectangle.y + @intCast(isize, rectangle.height) - 1;

        canvas.drawLine(l, t, r - 1, t, top_left);
        canvas.drawLine(l, t, l, b - 1, top_left);

        canvas.drawLine(l, b, r, b, bottom_right);
        canvas.drawLine(r, t, r, b, bottom_right);
    }

    pub fn drawRectangle(self: *Self, rect: Rectangle, bevel: Bevel) void {
        var canvas = Canvas.init(self);
        switch (bevel) {
            .edge => {
                drawRectangleImpl(&canvas, rect, self.scheme.bright_3d, self.scheme.medium_3d);
                drawRectangleImpl(&canvas, rect.shrink(1), self.scheme.medium_3d, self.scheme.bright_3d);
            },
            .crease => {
                drawRectangleImpl(&canvas, rect, self.scheme.medium_3d, self.scheme.bright_3d);
                drawRectangleImpl(&canvas, rect.shrink(1), self.scheme.bright_3d, self.scheme.medium_3d);
            },

            .raised => {
                drawRectangleImpl(&canvas, rect, self.scheme.bright_3d, self.scheme.medium_3d);
            },

            .sunken => {
                drawRectangleImpl(&canvas, rect, self.scheme.medium_3d, self.scheme.bright_3d);
            },

            .input_field => {
                drawRectangleImpl(&canvas, rect, self.scheme.medium_3d, self.scheme.bright_3d);
                drawRectangleImpl(&canvas, rect.shrink(1), self.scheme.dark_3d, self.scheme.background);
            },

            .button_default => {
                drawRectangleImpl(&canvas, rect, self.scheme.bright_3d, self.scheme.dark_3d);
                drawRectangleImpl(&canvas, rect.shrink(1), self.scheme.background, self.scheme.medium_3d);
            },

            .button_active => {
                drawRectangleImpl(&canvas, rect, self.scheme.black_3d, self.scheme.black_3d);
                drawRectangleImpl(&canvas, rect.shrink(1), self.scheme.bright_3d, self.scheme.dark_3d);
                drawRectangleImpl(&canvas, rect.shrink(2), self.scheme.background, self.scheme.medium_3d);
            },

            .button_pressed => {
                drawRectangleImpl(&canvas, rect, self.scheme.black_3d, self.scheme.black_3d);
                drawRectangleImpl(&canvas, rect.shrink(1), self.scheme.medium_3d, self.scheme.medium_3d);
            },
        }
    }

    pub fn drawHLine(self: *Self, x0: isize, y0: isize, width: usize, style: LineStyle) void {
        var canvas = Canvas.init(self);
        canvas.drawLine(
            x0,
            y0,
            x0 + @intCast(isize, width) - 1,
            y0,
            if (style == .edge) self.scheme.bright_3d else self.scheme.medium_3d,
        );
        canvas.drawLine(
            x0,
            y0 + 1,
            x0 + @intCast(isize, width) - 1,
            y0 + 1,
            if (style == .edge) self.scheme.medium_3d else self.scheme.bright_3d,
        );
    }

    pub fn drawVLine(self: *Self, x0: isize, y0: isize, height: usize, style: LineStyle) void {
        var canvas = Canvas.init(self);
        canvas.drawLine(
            x0,
            y0,
            x0,
            y0 + @intCast(isize, height) - 1,
            if (style == .edge) self.scheme.bright_3d else self.scheme.medium_3d,
        );
        canvas.drawLine(
            x0 + 1,
            y0 + 1,
            x0 + 1,
            y0 + @intCast(isize, height) - 1,
            if (style == .edge) self.scheme.medium_3d else self.scheme.bright_3d,
        );
    }

    fn scaleInt(ival: isize, scale: f32) isize {
        return @floatToInt(isize, std.math.round(@intToFloat(f32, ival) * scale));
    }

    pub fn measureString(self: *Self, text: []const u8, font: Font, line_width: ?usize) Size {}

    pub fn drawString(self: *Self, text: []const u8, target: Rectangle, font: Font, alignment: TextAlign) void {
        var canvas = Canvas.init(self);
        const font_cache = switch (font) {
            .monospace => &fonts.mono,
            .sans => &fonts.sans,
            .serif => &fonts.serif,
        };

        var utf8 = std.unicode.Utf8Iterator{
            .bytes = text,
            .i = 0,
        };

        var x: isize = target.x;
        var y: isize = target.y;

        var dx: isize = 0;
        var dy: isize = scaleInt(font_cache.ascent, font_cache.scale);

        var previous_codepoint: ?u24 = null;
        while (utf8.nextCodepoint()) |codepoint| {
            if (codepoint == '\n') {
                dx = 0;
                dy += scaleInt(font_cache.ascent - font_cache.descent + font_cache.line_gap, font_cache.scale);
                previous_codepoint = null;
                continue;
            }

            const glyph = font_cache.getGlyph(codepoint) catch continue;

            if (previous_codepoint) |prev| {
                dx += c.stbtt_GetCodepointKernAdvance(&font_cache.font, prev, codepoint);
            }
            previous_codepoint = codepoint;

            canvas.copyRectangle(
                x + scaleInt(dx + glyph.left_side_bearing, font_cache.scale),
                y + glyph.offset_y + dy,
                0,
                0,
                glyph.width,
                glyph.height,
                glyph,
                Glyph.getPixel,
            );

            dx += glyph.advance_width;
        }
    }

    pub fn pushClipRect(self: *Self, rectangle: Rectangle) !Rectangle {}

    pub fn popClipRect() void {}
};

// get the bbox of the bitmap centered around the glyph origin; so the
// bitmap width is ix1-ix0, height is iy1-iy0, and location to place
// the bitmap top left is (leftSideBearing*scale,iy0).
// (Note that the bitmap uses y-increases-down, but the shape uses
// y-increases-up, so CodepointBitmapBox and CodepointBox are inverted.)

const Glyph = struct {
    const Self = @This();

    /// row-major grayscale pixels of the target map
    pixels: []u8,

    /// width of the image in pixels
    width: usize,

    /// height of the image in pixels
    height: usize,

    /// offset to the base line
    offset_y: isize,

    /// advanceWidth is the offset from the current horizontal position to the next horizontal position
    /// these are expressed in unscaled coordinates
    advance_width: isize,

    /// leftSideBearing is the offset from the current horizontal position to the left edge of the character
    left_side_bearing: isize,

    fn getPixel(self: Self, x: isize, y: isize) Color {
        if (x < 0 or y < 0)
            return Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
        if (x >= @intCast(isize, self.width) or y >= @intCast(isize, self.height))
            return Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

        const graylevel = self.pixels[std.math.absCast(y) * self.width + std.math.absCast(x)];

        return Color{
            .r = 0x00,
            .g = 0x00,
            .b = 0x00,
            .a = graylevel,
        };
    }
};

const FontBuffer = struct {
    const Self = @This();

    font: c.stbtt_fontinfo,
    allocator: *std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    glyphs: std.AutoHashMap(u24, Glyph),

    font_size: usize,

    ascent: isize,
    descent: isize,
    line_gap: isize,

    /// Scale of `advance_width` and `left_side_bearing`
    scale: f32,

    fn init(allocator: *std.mem.Allocator, ttf: []const u8, font_size: usize) !Self {
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
            .ascent = ascent,
            .descent = descent,
            .line_gap = line_gap,
            .scale = c.stbtt_ScaleForPixelHeight(&info, @intToFloat(f32, font_size)),
        };
    }

    fn deinit(self: *Self) void {
        self.glyphs.deinit();
        self.arena.deinit();
        self.* = undefined;
    }

    fn getGlyph(self: *Self, codepoint: u24) !Glyph {
        if (self.glyphs.get(codepoint)) |glyph| {
            return glyph;
        } else {
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

            const width: usize = @intCast(usize, ix1 - ix0);
            const height: usize = @intCast(usize, iy1 - iy0);

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
                .advance_width = advance_width,
                .left_side_bearing = left_side_bearing,
                .offset_y = iy0,
            };

            try self.glyphs.put(codepoint, glyph);

            return glyph;
        }
    }
};

const fonts = struct {
    var mono: FontBuffer = undefined;
    var sans: FontBuffer = undefined;
    var serif: FontBuffer = undefined;
};

pub fn init(allocator: *std.mem.Allocator) !void {
    fonts.serif = try FontBuffer.init(allocator, @embedFile("./fonts/CrimsonPro-Regular.ttf"), 20);
    fonts.sans = try FontBuffer.init(allocator, @embedFile("./fonts/Roboto-Regular.ttf"), 20);
    fonts.mono = try FontBuffer.init(allocator, @embedFile("./fonts/SourceCodePro-Regular.ttf"), 20);

    std.debug.print("{}\n", .{fonts.sans});
}

pub fn deinit() void {
    fonts.serif.deinit();
    fonts.sans.deinit();
    fonts.mono.deinit();
}

// int main(int argc, char **argv)
// {
//    stbtt_fontinfo font;
//    unsigned char *bitmap;
//    int w,h,i,j,c = (argc > 1 ? atoi(argv[1]) : 'a'), s = (argc > 2 ? atoi(argv[2]) : 20);

//    fread(ttf_buffer, 1, 1<<25, fopen(argc > 3 ? argv[3] : "c:/windows/fonts/arialbd.ttf", "rb"));

//    stbtt_InitFont(&font, ttf_buffer, stbtt_GetFontOffsetForIndex(ttf_buffer,0));
//    bitmap = stbtt_GetCodepointBitmap(&font, 0,stbtt_ScaleForPixelHeight(&font, s), c, &w, &h, 0,0);

//    for (j=0; j < h; ++j) {
//       for (i=0; i < w; ++i)
//          putchar(" .:ioVM@"[bitmap[j*w+i]>>5]);
//       putchar('\n');
//    }
//    return 0;
// }

// STBTT_DEF unsigned char *stbtt_GetCodepointBitmap(const stbtt_fontinfo *info, float scale_x, float scale_y, int codepoint, int *width, int *height, int *xoff, int *yoff)

// STBTT_DEF float stbtt_ScaleForPixelHeight(const stbtt_fontinfo *info, float height);

// void stbtt_GetCodepointBitmapBox(const stbtt_fontinfo *font, int codepoint, float scale_x, float scale_y, int *ix0, int *iy0, int *ix1, int *iy1)
// void stbtt_MakeCodepointBitmap(const stbtt_fontinfo *info, unsigned char *output, int out_w, int out_h, int out_stride, float scale_x, float scale_y, int codepoint)
// void stbtt_GetCodepointHMetrics(const stbtt_fontinfo *info, int codepoint, int *advanceWidth, int *leftSideBearing);

// void stbtt_GetFontVMetrics(const stbtt_fontinfo *info, int *ascent, int *descent, int *lineGap)

// int  stbtt_GetCodepointKernAdvance(const stbtt_fontinfo *info, int ch1, int ch2);
// an additional amount to add to the 'advance' value between ch1 and ch2

//   "Load" a font file from a memory buffer (you have to keep the buffer loaded)
//           stbtt_InitFont()
//           stbtt_GetFontOffsetForIndex()        -- indexing for TTC font collections
//           stbtt_GetNumberOfFonts()             -- number of fonts for TTC font collections
//
//   Render a unicode codepoint to a bitmap
//           stbtt_GetCodepointBitmap()           -- allocates and returns a bitmap
//           stbtt_MakeCodepointBitmap()          -- renders into bitmap you provide
//           stbtt_GetCodepointBitmapBox()        -- how big the bitmap must be
//
//   Character advance/positioning
//           stbtt_GetCodepointHMetrics()
//           stbtt_GetFontVMetrics()
//           stbtt_GetFontVMetricsOS2()
//           stbtt_GetCodepointKernAdvance()

const std = @import("std");
const args_parser = @import("args");

const string_luts = @import("strings.zig");
const enums = @import("enums.zig");

const FileType = enum { binary, header };

pub fn main() !u8 {
    const args = try args_parser.parseForCurrentProcess(struct {
        // This declares long options for double hyphen
        output: ?[]const u8 = null,
        config: ?[]const u8 = null,
        @"file-type": FileType = .binary,
        @"update-config": bool = false,

        // This declares short-hand options for single hyphen
        pub const shorthands = .{
            .u = "update-config",
            .f = "file-type",
            .c = "config",
            .o = "output",
        };
    }, std.heap.page_allocator);
    defer args.deinit();

    switch (args.positionals.len) {
        0 => {
            try std.io.getStdOut().outStream().print("usage: {} [-c config] [-u] [-o output] layoutfile\n", .{
                args.exeName,
            });
            return 1;
        },
        2 => {
            try std.io.getStdOut().outStream().writeAll("invalid number of args!\n");
            return 1;
        },
        else => {},
    }

    var config: ?std.json.ValueTree = null;
    defer if (config) |*cfg|
        cfg.deinit();

    if (args.options.config) |cfgfile| {
        var file = try std.fs.cwd().openFile(cfgfile, .{ .read = true, .write = false });
        defer file.close();

        const buffer = try file.inStream().readAllAlloc(std.heap.page_allocator, 1 << 20); // 1 MB
        errdefer std.heap.page_allocator.free(buffer);

        // Don't clone strings, we just let the buffer dangle, will be freed at the end
        // anyways
        var parser = std.json.Parser.init(std.heap.page_allocator, false);
        defer parser.deinit();

        config = try parser.parse(buffer);
    }

    const inputFile = args.positionals[0];

    var src = blk: {
        var file = std.fs.cwd().openFile(inputFile, .{ .read = true, .write = false }) catch |err| switch (err) {
            error.FileNotFound => {
                try std.io.getStdOut().outStream().writeAll("could not read the input file!\n");
                return 1;
            },
            else => return err,
        };
        defer file.close();

        break :blk try file.inStream().readAllAlloc(std.heap.page_allocator, 4 << 20); // max. 4 MB
    };
    defer std.heap.page_allocator.free(src);

    // const outfile_path = if (args.options.output == null) |outfile| outfile else {
    //     try std.io.getStdOut().outStream().writeAll("implicit outfile not supported yet!\n");
    //     return 1;
    // };

    var data = std.ArrayList(u8).init(std.heap.page_allocator);
    defer data.deinit();

    {
        var outstream = data.outStream();

        try outstream.writeAll("HELLO");

        var tokenIterator = TokenIterator.init(src);
        while (try tokenIterator.nextSkipWhitespace()) |token| {
            std.debug.warn("token: {}\n", .{token});
        }
    }

    std.debug.warn("result:\n{X}\n", .{data.items});

    return 1;
}

const TokenType = enum {
    identifier,
    integer,
    number,
    openBrace,
    closeBrace,
    colon,
    semiColon,
    comma,
    string,
    percentage,
    openParens,
    closeParens,
    whitespace,
};

const Token = struct {
    const Self = @This();
    type: TokenType,
    text: []const u8,

    fn initSingle(text: []const u8, kind: TokenType) Token {
        return Token{
            .type = kind,
            .text = text[0..1],
        };
    }
};

const TokenIterator = struct {
    const Self = @This();

    data: []const u8,

    fn init(src: []const u8) Self {
        return Self{
            .data = src,
        };
    }

    fn isIdentifierChar(c: u8) bool {
        return switch (c) {
            'a'...'z', 'A'...'Z', '-' => true,
            else => false,
        };
    }

    fn isWhitespace(c: u8) bool {
        return switch (c) {
            ' ', '\n', '\r', '\t' => true,
            else => false,
        };
    }

    fn isDigit(c: u8) bool {
        return switch (c) {
            '0'...'9' => true,
            else => false,
        };
    }

    fn nextSkipWhitespace(self: *Self) !?Token {
        while (true) {
            var item = try self.next();
            if (item == null)
                return null;
            if (item.?.type != .whitespace)
                return item;
        }
    }

    fn next(self: *Self) !?Token {
        if (self.data.len == 0)
            return null;
        const c = self.data[0];
        const token = switch (c) {
            // Single character tokens,
            '{' => Token.initSingle(self.data, .openBrace),
            '}' => Token.initSingle(self.data, .closeBrace),
            '(' => Token.initSingle(self.data, .openParens),
            ')' => Token.initSingle(self.data, .closeParens),
            ':' => Token.initSingle(self.data, .colon),
            ';' => Token.initSingle(self.data, .semiColon),
            ',' => Token.initSingle(self.data, .comma),

            // Identifier
            'a'...'z', 'A'...'Z' => blk: {
                var offset: usize = 0;
                while (offset < self.data.len and isIdentifierChar(self.data[offset])) {
                    offset += 1;
                }
                break :blk Token{
                    .type = .identifier,
                    .text = self.data[0..offset],
                };
            },

            // Numbers (integer, number, percentage)
            '0'...'9' => blk: {
                var offset: usize = 0;
                while (offset < self.data.len and isDigit(self.data[offset])) {
                    offset += 1;
                }
                if (offset < self.data.len) {
                    if (self.data[offset] == '%') {
                        break :blk Token{
                            .type = .percentage,
                            .text = self.data[0 .. offset + 1],
                        };
                    }
                    if (self.data[offset] == '.') {
                        offset += 1;
                        while (offset < self.data.len and isDigit(self.data[offset])) {
                            offset += 1;
                        }
                        break :blk Token{
                            .type = .number,
                            .text = self.data[0..offset],
                        };
                    }
                }
                break :blk Token{
                    .type = .integer,
                    .text = self.data[0..offset],
                };
            },

            // string
            '"' => blk: {
                var offset: usize = 1;
                while (offset < self.data.len and self.data[offset] != '"' and self.data[offset] != '\n') {
                    offset += 1;
                }
                if (offset >= self.data.len)
                    return error.IncompleteString;
                if (self.data[offset] != '"')
                    return error.IncompleteString;
                break :blk Token{
                    .type = .string,
                    .text = self.data[0 .. offset + 1],
                };
            },

            ' ', '\n', '\r', '\t' => Token.initSingle(self.data, .whitespace),

            else => return error.UnrecognizedChar,
        };
        self.data = self.data[token.text.len..];
        return token;
    }
};

test "Tokenizer single chars" {
    const tests = .{
        .{ "{", .openBrace },
        .{ "}", .closeBrace },
        .{ "(", .openParens },
        .{ ")", .closeParens },
        .{ ":", .colon },
        .{ ";", .semiColon },
        .{ ",", .comma },
        .{ "{heajsdkj", .openBrace },
        .{ "}heajsdkj", .closeBrace },
        .{ "(heajsdkj", .openParens },
        .{ ")heajsdkj", .closeParens },
        .{ ":heajsdkj", .colon },
        .{ ";heajsdkj", .semiColon },
        .{ ",heajsdkj", .comma },
    };

    inline for (tests) |t| {
        const text = t.@"0";
        const result = t.@"1";

        std.testing.expectEqual(Token{
            .type = result,
            .text = text[0..1],
        }, (try TokenIterator.init(text).next()).?);
    }
}

test "Tokenizer identifier" {
    const tests_good = .{
        "a",
        "ahadsad",
        "SJADJSALD",
        "hello-world",
        "HELLworld",
        "h-s",
        "AB",
    };

    inline for (tests_good) |t| {
        std.testing.expectEqual(Token{
            .type = .identifier,
            .text = t,
        }, (try TokenIterator.init(t).next()).?);
    }
}

test "Tokenizer numbers" {
    const tests = .{
        .{ "0", .integer },
        .{ "11", .integer },
        .{ "123", .integer },
        .{ "0.0", .number },
        .{ "123.213", .number },
        .{ "32434%", .percentage },
        .{ "34%", .percentage },
        .{ "0%", .percentage },
    };

    inline for (tests) |t| {
        const text = t.@"0";
        const result = t.@"1";

        std.testing.expectEqual(Token{
            .type = result,
            .text = text,
        }, (try TokenIterator.init(text).next()).?);
    }
}

test "Tokenizer strings" {
    const tests_good = .{
        "\"a\"",
        "\"ahadsad\"",
        "\"SJADJSALD\"",
        "\"hello-world\"",
        "\"HELLworld\"",
        "\"h-s\"",
        "\"AB\"",
    };

    inline for (tests_good) |t| {
        std.testing.expectEqual(Token{
            .type = .string,
            .text = t,
        }, (try TokenIterator.init(t).next()).?);
    }
}

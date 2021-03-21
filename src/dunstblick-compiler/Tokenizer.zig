const std = @import("std");

const Location = @import("Location.zig");

pub const TokenType = enum {
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

pub const Token = struct {
    const Self = @This();
    type: TokenType,
    text: []const u8,
    location: Location,
};

const Self = @This();

data: []const u8,
location: Location,
peekedToken: ?Token, // only used for nextSkipWhitespace, peekNextWhitespace

pub fn init(src: []const u8) Self {
    return Self{
        .data = src,
        .location = Location{
            .line = 1,
            .column = 1,
        },
        .peekedToken = null,
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

fn initSingle(text: []const u8, kind: TokenType) Token {
    return Token{
        .type = kind,
        .text = text[0..1],
        .location = undefined,
    };
}

pub fn readUntil(self: *Self, types: anytype) !void {
    while (true) {
        var token_or_null = try self.nextSkipWhitespace();
        if (token_or_null) |token| {
            inline for (types) |t| {
                if (token.type == t)
                    return;
            }
        } else {
            return;
        }
    }
}

pub fn expect(self: *Self, _type: TokenType) !Token {
    var tok = try self.nextSkipWhitespace();
    if (tok) |t| {
        if (t.type != _type)
            return error.UnexpectedToken;
        return t;
    } else {
        return error.UnexpectedEndOfStream;
    }
}

pub fn expectOneOf(self: *Self, comptime types: anytype) !Token {
    var token = try self.nextSkipWhitespace();
    if (token) |tok| {
        inline for (types) |t| {
            if (tok.type == t)
                return tok;
        }
        std.debug.warn("found: {}\n", .{tok});
        return error.UnexpectedToken;
    } else {
        return error.UnexpectedEndOfStream;
    }
}

pub fn peekNextWhitespace(self: *Self) !?Token {
    if (self.peekedToken) |tok|
        return tok;
    self.peekedToken = try self.nextSkipWhitespace();
    return self.peekedToken;
}

fn nextSkipWhitespace(self: *Self) !?Token {
    if (self.peekedToken) |tok| {
        const copy = tok;
        self.peekedToken = null;
        return tok;
    }

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
    const chr = self.data[0];
    var token = switch (chr) {
        // Single character tokens,
        '{' => initSingle(self.data, .openBrace),
        '}' => initSingle(self.data, .closeBrace),
        '(' => initSingle(self.data, .openParens),
        ')' => initSingle(self.data, .closeParens),
        ':' => initSingle(self.data, .colon),
        ';' => initSingle(self.data, .semiColon),
        ',' => initSingle(self.data, .comma),

        // Identifier
        'a'...'z', 'A'...'Z' => blk: {
            var offset: usize = 0;
            while (offset < self.data.len and isIdentifierChar(self.data[offset])) {
                offset += 1;
            }
            break :blk Token{
                .type = .identifier,
                .text = self.data[0..offset],
                .location = undefined,
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
                        .location = undefined,
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
                        .location = undefined,
                    };
                }
            }
            break :blk Token{
                .type = .integer,
                .text = self.data[0..offset],
                .location = undefined,
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
                .location = undefined,
            };
        },

        ' ', '\n', '\r', '\t' => initSingle(self.data, .whitespace),

        // comment
        '/' => blk: {
            if (self.data.len < 4)
                return error.UnexpectedEndOfStream;
            if (self.data[1] != '*')
                return error.UnexpectedToken;

            var offset: usize = 3;
            while (offset < self.data.len and self.data[offset - 1] != '*' and self.data[offset] != '/') {
                offset += 1;
            }
            if (offset >= self.data.len)
                return error.UnexpectedEndOfStream;
            offset += 1;
            break :blk Token{
                .type = .whitespace,
                .text = self.data[0..offset],
                .location = undefined,
            };
        },

        else => return error.UnrecognizedChar,
    };
    token.location = self.location;

    for (token.text) |c| {
        if (c == '\n') {
            self.location.line += 1;
            self.location.column = 1;
        } else {
            self.location.column += 1;
        }
    }

    self.data = self.data[token.text.len..];
    return token;
}

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
            .location = Location{ .line = 1, .column = 1 },
        }, (try Self.init(text).next()).?);
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
            .location = Location{ .line = 1, .column = 1 },
        }, (try Self.init(t).next()).?);
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
            .location = Location{ .line = 1, .column = 1 },
        }, (try Self.init(text).next()).?);
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
            .location = Location{ .line = 1, .column = 1 },
        }, (try Self.init(t).next()).?);
    }
}

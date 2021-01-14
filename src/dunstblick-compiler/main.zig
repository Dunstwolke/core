const std = @import("std");
const args_parser = @import("args");

const string_luts = @import("strings.zig");
const enums = @import("enums.zig");

const FileType = enum { binary, header };

const IDMap = std.StringHashMap(u32);

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
            try std.io.getStdOut().writer().print("usage: {} [-c config] [-u] [-o output] layoutfile\n", .{
                args.executable_name,
            });
            return 1;
        },
        2 => {
            try std.io.getStdOut().writer().writeAll("invalid number of args!\n");
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

        const buffer = try file.reader().readAllAlloc(std.heap.page_allocator, 1 << 20); // 1 MB
        errdefer std.heap.page_allocator.free(buffer);

        // Don't clone strings, we just let the buffer dangle, will be freed at the end
        // anyways
        var parser = std.json.Parser.init(std.heap.page_allocator, false);
        defer parser.deinit();

        config = try parser.parse(buffer);

        validateConfig(config.?) catch |err| {
            try std.io.getStdOut().writer().writeAll("invalid config file!\n");
            return 1;
        };
    }

    var resources = IDMap.init(std.heap.page_allocator);
    defer resources.deinit();

    var events = IDMap.init(std.heap.page_allocator);
    defer events.deinit();

    var variables = IDMap.init(std.heap.page_allocator);
    defer variables.deinit();

    var objects = IDMap.init(std.heap.page_allocator);
    defer objects.deinit();

    const inputFile = args.positionals[0];

    var src = blk: {
        var file = std.fs.cwd().openFile(inputFile, .{ .read = true, .write = false }) catch |err| switch (err) {
            error.FileNotFound => {
                try std.io.getStdOut().writer().writeAll("could not read the input file!\n");
                return 1;
            },
            else => return err,
        };
        defer file.close();

        break :blk try file.reader().readAllAlloc(std.heap.page_allocator, 4 << 20); // max. 4 MB
    };
    defer std.heap.page_allocator.free(src);

    if (config) |cfg| {
        try loadIdMap(cfg, "resources", &resources);
        try loadIdMap(cfg, "callbacks", &events);
        try loadIdMap(cfg, "properties", &variables);
        try loadIdMap(cfg, "objects", &objects);
    }

    const outfile_path = if (args.options.output) |outfile| outfile else {
        try std.io.getStdOut().writer().writeAll("implicit outfile not supported yet!\n");
        return 1;
    };

    var data = std.ArrayList(u8).init(std.heap.page_allocator);
    defer data.deinit();

    var errors = ErrorCollection.init(std.heap.page_allocator);
    defer errors.deinit();

    const success = blk: {
        var outstream = data.writer();

        var tokenIterator = TokenIterator.init(src);

        var parser = Parser{
            .allocator = std.heap.page_allocator,
            .tokens = &tokenIterator,
            .errors = &errors,

            .allow_new_items = args.options.@"update-config",
            .resources = &resources,
            .events = &events,
            .variables = &variables,
            .objects = &objects,
        };

        parseFile(parser, &outstream) catch |err| {
            std.debug.print("{}:{}: error: {}\n", .{
                inputFile,
                tokenIterator.location,
                err,
            });
            return err;
            // break :blk false;
        };

        break :blk true;
    };

    if (errors.list.items.len > 0) {
        for (errors.list.items) |err| {
            std.debug.print("error: {}\n", .{err});
        }
        return 1;
    }

    if (success == false) {
        return 1;
    }

    {
        var file = try std.fs.cwd().createFile(outfile_path, .{ .exclusive = false, .read = false });
        defer file.close();

        var stream = file.writer();

        switch (args.options.@"file-type") {
            .binary => try stream.writeAll(data.items),

            .header => {
                for (data.items) |c, i| {
                    try stream.print("0x{X}, ", .{c});
                }
            },
        }
    }

    return 0;
}

fn validateObjectMap(list: std.json.Value) !void {
    if (list != .Object)
        return error.InvalidConfig;
    var iter = list.Object.iterator();
    while (iter.next()) |kv| {
        if (kv.value != .Integer)
            return error.InvalidConfig;
    }
}

fn validateConfig(config: std.json.ValueTree) !void {
    const root = config.root;
    if (root != .Object)
        return error.InvalidConfig;

    if (root.Object.get("resources")) |value| {
        try validateObjectMap(value);
    }
    if (root.Object.get("properties")) |value| {
        try validateObjectMap(value);
    }
    if (root.Object.get("callbacks")) |value| {
        try validateObjectMap(value);
    }
    if (root.Object.get("objects")) |value| {
        try validateObjectMap(value);
    }
}

fn loadIdMap(config: std.json.ValueTree, key: []const u8, map: *IDMap) !void {
    if (config.root.Object.get(key)) |value| {
        var items = value.Object.iterator();
        while (items.next()) |kv| {
            try map.put(kv.key, @intCast(u32, kv.value.Integer));
        }
    }
}

fn widgetFromName(name: []const u8) ?enums.WidgetType {
    inline for (string_luts.widget_types) |tup| {
        if (std.mem.eql(u8, tup.widget, name))
            return tup.type;
    }
    return null;
}

fn propertyFromName(name: []const u8) ?enums.Property {
    inline for (string_luts.properties) |tup| {
        if (std.mem.eql(u8, tup.property, name))
            return tup.value;
    }
    return null;
}

const WidgetOrProperty = union(enum) {
    widget: enums.WidgetType,
    property: enums.Property,
};

fn widgetOrPropertyFromName(name: []const u8) ?WidgetOrProperty {
    if (propertyFromName(name)) |prop|
        return WidgetOrProperty{ .property = prop };
    if (widgetFromName(name)) |widget|
        return WidgetOrProperty{ .widget = widget };
    return null;
}

fn getTypeOfProperty(prop: enums.Property) enums.Type {
    inline for (string_luts.properties) |v| {
        if (v.value == prop)
            return v.type;
    }
    unreachable;
}

const CompileError = struct {
    where: Location,
    message: []const u8,

    pub fn format(value: @This(), fmt: []const u8, options: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.print("{}: {}", .{
            value.where,
            value.message,
        });
    }
};

const ErrorCollection = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    list: std.ArrayList(CompileError),

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .list = std.ArrayList(CompileError).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.list.deinit();
        self.* = undefined;
    }

    pub fn add(self: *Self, where: Location, comptime fmt: []const u8, args: anytype) !void {
        const msg = try std.fmt.allocPrint(&self.arena.allocator, fmt, args);
        errdefer self.arena.allocator.free(msg);

        try self.list.append(CompileError{
            .where = where,
            .message = msg,
        });
    }
};

const Parser = struct {
    allocator: *std.mem.Allocator,
    tokens: *TokenIterator,
    errors: *ErrorCollection,

    allow_new_items: bool,
    resources: *IDMap,
    events: *IDMap,
    variables: *IDMap,
    objects: *IDMap,
};

fn parseFile(parser: Parser, writer: anytype) !void {
    var identifier = try parser.tokens.expect(.identifier);
    try parseWidget(parser, writer, identifier.text);
}

fn tokenToInteger(tok: Token) !i32 {
    if (tok.type != .integer)
        return error.UnexpectedToken;
    return try std.fmt.parseInt(i32, tok.text, 10);
}

fn tokenToUnsignedInteger(tok: Token) !u32 {
    if (tok.type != .integer)
        return error.UnexpectedToken;
    return try std.fmt.parseInt(u32, tok.text, 10);
}

fn tokenToNumber(tok: Token) !f32 {
    if (tok.type != .number)
        return error.UnexpectedToken;
    return try std.fmt.parseFloat(f32, tok.text);
}

fn parseString(parser: Parser) ![]const u8 {
    var input = try parser.tokens.expect(.string);

    return try convertString(parser, input.text);
}

/// converts a raw string in token form "\"adksakd\\n\"" into
/// the *real* byte sequence "adksakd\n"
fn convertString(parser: Parser, input: []const u8) ![]const u8 {
    var output = try parser.allocator.alloc(u8, input.len - 2);
    errdefer parser.allocator.free(output);

    const State = union(enum) {
        default: void,
        escape: void,
    };

    var outptr: usize = 0;
    var state = State{ .default = {} };
    for (input[1 .. input.len - 1]) |c| {
        switch (state) {
            .escape => switch (c) {
                'r' => {
                    output[outptr] = '\r';
                    outptr += 1;
                },
                'n' => {
                    output[outptr] = '\n';
                    outptr += 1;
                },
                't' => {
                    output[outptr] = '\t';
                    outptr += 1;
                },
                else => {
                    output[outptr] = c;
                    outptr += 1;
                },
            },
            .default => switch (c) {
                '\\' => {},
                else => {
                    output[outptr] = c;
                    outptr += 1;
                },
            },
        }
    }

    return output[0..outptr];
}

fn parseID(parser: Parser, writer: anytype, functionName: []const u8, map: *IDMap) !void {
    var resource = parser.tokens.expect(.identifier) catch {
        try parser.errors.add(parser.tokens.location, "Expected identifier.", .{});
        try parser.tokens.readUntil(.{.semiColon});
        return;
    };
    if (!std.mem.eql(u8, resource.text, functionName)) {
        try parser.errors.add(
            parser.tokens.location,
            "Expected {}, found '{}'.",
            .{ functionName, resource.text },
        );
        try parser.tokens.readUntil(.{.semiColon});
        return;
    }
    _ = parser.tokens.expect(.openParens) catch {
        try parser.errors.add(parser.tokens.location, "Expected opening parens.", .{});
        try parser.tokens.readUntil(.{.semiColon});
        return;
    };

    var value = try parser.tokens.expectOneOf(.{ .integer, .string });
    const rid = switch (value.type) {
        .integer => try tokenToUnsignedInteger(value),
        .string => blk: {
            const name = try convertString(parser, value.text);
            defer parser.allocator.free(name);

            if (parser.allow_new_items) {
                const res = try map.getOrPut(name);
                if (!res.found_existing) {
                    var limit: u32 = 1;

                    var iter = map.iterator();
                    while (iter.next()) |kv| {
                        limit = std.math.max(kv.value, limit);
                    }

                    res.entry.value = limit + 1;
                }
                break :blk res.entry.value;
            } else {
                if (map.get(name)) |val| {
                    break :blk val;
                }

                try parser.errors.add(parser.tokens.location, "Unkown {} alias '{}'", .{ functionName, name });
            }
            break :blk @as(u32, 0);
        },
        else => unreachable,
    };
    _ = parser.tokens.expect(.closeParens) catch {
        try parser.errors.add(parser.tokens.location, "Expected closing parens.", .{});
        try parser.tokens.readUntil(.{.semiColon});
        return;
    };

    _ = parser.tokens.expect(.semiColon) catch {
        try parser.errors.add(parser.tokens.location, "Expected semicolon.", .{});
        try parser.tokens.readUntil(.{.semiColon});
        return;
    };

    try writeVarUInt(writer, rid);
}

fn parseProperty(parser: Parser, writer: anytype, property: enums.Property, propertyType: enums.Type) !void {
    if (try parser.tokens.peekNextWhitespace()) |tok| {
        if (tok.type == .identifier) {
            if (std.mem.eql(u8, tok.text, "bind")) {

                // this is a bindingx
                try writer.writeByte(@as(u8, @enumToInt(property)) | 0x80);

                try parseID(parser, writer, "bind", parser.variables);

                return;
            }
        }
    }

    try writer.writeByte(@enumToInt(property));

    switch (propertyType) {
        .invalid => unreachable,

        // integer;
        .integer => {
            var i = try tokenToInteger(try parser.tokens.expect(.integer));
            try writeVarSInt(writer, i);
            _ = try parser.tokens.expect(.semiColon);
        },

        // number;
        .number => {
            var f = try tokenToNumber(try parser.tokens.expect(.number));
            try writer.writeAll(std.mem.asBytes(&f));
            _ = try parser.tokens.expect(.semiColon);
        },

        // string;
        .string => {
            var string = try parseString(parser);
            defer parser.allocator.free(string);

            _ = try parser.tokens.expect(.semiColon);

            try writeVarUInt(writer, @intCast(u32, string.len));
            try writer.writeAll(string);
        },

        // identifier;
        .enumeration => {
            var name = try parser.tokens.expect(.identifier);
            _ = try parser.tokens.expect(.semiColon);

            const b = inline for (string_luts.enumerations) |e| {
                if (std.mem.eql(u8, e.enumeration, name.text))
                    break @as(enums.Enum, e.value);
            } else return error.UnknownEnum;

            try writer.writeByte(@enumToInt(b));
        },

        // Allowed formats:
        // number;
        // number,number;
        // number,number,number,number;
        .margins => {
            var first = try tokenToUnsignedInteger(try parser.tokens.expect(.integer));

            if ((try parser.tokens.expectOneOf(.{ .comma, .semiColon })).type == .comma) {
                var second = try tokenToUnsignedInteger(try parser.tokens.expect(.integer));

                if ((try parser.tokens.expectOneOf(.{ .comma, .semiColon })).type == .comma) {
                    var third = try tokenToUnsignedInteger(try parser.tokens.expect(.integer));

                    _ = try parser.tokens.expect(.comma);

                    var fourth = try tokenToUnsignedInteger(try parser.tokens.expect(.integer));

                    _ = try parser.tokens.expect(.semiColon);

                    try writeVarUInt(writer, first);
                    try writeVarUInt(writer, second);
                    try writeVarUInt(writer, third);
                    try writeVarUInt(writer, fourth);
                } else {
                    try writeVarUInt(writer, first);
                    try writeVarUInt(writer, second);
                    try writeVarUInt(writer, first);
                    try writeVarUInt(writer, second);
                }
            } else {
                try writeVarUInt(writer, first);
                try writeVarUInt(writer, first);
                try writeVarUInt(writer, first);
                try writeVarUInt(writer, first);
            }
        },

        .color => {
            unreachable;
        },

        // integer, integer;
        .size => {
            var width = try tokenToUnsignedInteger(try parser.tokens.expect(.identifier));
            _ = try parser.tokens.expect(.identifier);
            var height = try tokenToUnsignedInteger(try parser.tokens.expect(.identifier));
            _ = try parser.tokens.expect(.semiColon);

            try writeVarUInt(writer, width);
            try writeVarUInt(writer, height);
        },

        // integer, integer;
        .point => {
            var width = try tokenToInteger(try parser.tokens.expect(.identifier));
            _ = try parser.tokens.expect(.identifier);
            var height = try tokenToInteger(try parser.tokens.expect(.identifier));
            _ = try parser.tokens.expect(.semiColon);

            try writeVarSInt(writer, width);
            try writeVarSInt(writer, height);
        },

        .resource => try parseID(parser, writer, "resource", parser.resources),

        // true|false|yes|no;
        .boolean => {
            var name = try parser.tokens.expect(.identifier);
            _ = try parser.tokens.expect(.semiColon);

            const values = .{
                .{ .text = "true", .value = true },
                .{ .text = "yes", .value = true },
                .{ .text = "false", .value = false },
                .{ .text = "no", .value = false },
            };

            const val = inline for (values) |v| {
                if (std.mem.eql(u8, v.text, name.text))
                    break v.value;
            } else return error.UnknownEnum;

            try writer.writeByte(@boolToInt(val));
        },

        // (identifier|percentage|integer)
        .sizelist => {
            // bitmask containing two bits per entry:
            // 00 = auto
            // 01 = expand
            // 10 = integer / pixels
            // 11 = number / percentage
            const SizeType = enum(u2) {
                auto = 0b00,
                expand = 0b01,
                pixels = 0b10,
                percentage = 0b11,
            };
            const SizeEntry = union(SizeType) {
                auto: void,
                expand: void,
                pixels: u32,
                percentage: u7,
            };

            var list = std.ArrayList(SizeEntry).init(parser.allocator);
            defer list.deinit();

            while (true) {
                var item = try parser.tokens.expectOneOf(.{ .percentage, .integer, .identifier });
                switch (item.type) {
                    .percentage => {
                        try list.append(SizeEntry{
                            .percentage = try std.fmt.parseInt(u7, item.text[0 .. item.text.len - 1], 10),
                        });
                    },
                    .integer => {
                        try list.append(SizeEntry{
                            .pixels = try tokenToUnsignedInteger(item),
                        });
                    },
                    .identifier => {
                        if (std.mem.eql(u8, item.text, "auto")) {
                            try list.append(SizeEntry{
                                .auto = {},
                            });
                        } else if (std.mem.eql(u8, item.text, "expand")) {
                            try list.append(SizeEntry{
                                .expand = {},
                            });
                        } else {
                            return error.UnexpectedToken;
                        }
                    },
                    else => unreachable,
                }
                if ((try parser.tokens.expectOneOf(.{ .comma, .semiColon })).type == .semiColon)
                    break;
            }

            try writeVarUInt(writer, @intCast(u32, list.items.len));

            {
                var i: usize = 0;
                while (i < list.items.len) : (i += 4) {
                    var value: u8 = 0;

                    var j: usize = 0;
                    while (j < std.math.min(4, list.items.len - i)) : (j += 1) {
                        value |= @as(u8, @enumToInt(@as(SizeType, list.items[i + j]))) << @intCast(u3, 2 * j);
                    }

                    try writer.writeByte(value);
                }
            }

            for (list.items) |item| {
                switch (item) {
                    .pixels => |v| try writeVarUInt(writer, v),
                    .percentage => |v| try writer.writeByte(@as(u8, v) | 0x80),
                    else => {},
                }
            }
        },

        .object => try parseID(parser, writer, "object", parser.objects),

        .objectlist => {
            unreachable;
        },

        .event => try parseID(parser, writer, "callback", parser.events),
        .name => try parseID(parser, writer, "widget", parser.events),
    }
}

const ParseWidgetError = error{
    OutOfMemory,
    UnexpectedToken,
    UnrecognizedChar,
    IncompleteString,
    UnexpectedEndOfStream,
    Overflow,
    InvalidCharacter,
    UnknownEnum,
};
fn parseWidget(parser: Parser, writer: anytype, widgetTypeName: []const u8) ParseWidgetError!void {
    if (widgetFromName(widgetTypeName)) |widget| {
        try writer.writeByte(@enumToInt(widget));
    } else {
        try parser.errors.add(
            parser.tokens.location,
            "Unkown widget type {}",
            .{widgetTypeName},
        );
    }

    _ = try parser.tokens.expect(.openBrace);

    var isReadingChildren = false;
    while (true) {
        var id_or_closing = try parser.tokens.expectOneOf(.{ .identifier, .closeBrace });
        switch (id_or_closing.type) {
            .closeBrace => {
                if (!isReadingChildren) {
                    try writer.writeByte(0); // end of properties
                }
                try writer.writeByte(0); // end of children
                break;
            },

            .identifier => {
                var widgetOrProperty = if (widgetOrPropertyFromName(id_or_closing.text)) |wop| wop else {
                    // TODO: try to recover here!
                    try parser.errors.add(
                        parser.tokens.location,
                        "Unkown widget or property '{}'",
                        .{id_or_closing.text},
                    );
                    try parser.tokens.readUntil(.{ .semiColon, .closeBrace });
                    continue;
                };

                switch (widgetOrProperty) {
                    .widget => |widget| {
                        if (!isReadingChildren) {
                            // write end of properties
                            try writer.writeByte(0);
                        }
                        isReadingChildren = true;

                        try parseWidget(parser, writer, id_or_closing.text);
                    },
                    .property => |prop| {
                        if (isReadingChildren) {
                            try parser.errors.add(parser.tokens.location, "Properties are not allowed after the first child definition!", .{});
                        }
                        _ = try parser.tokens.expect(.colon);

                        const propertyType = getTypeOfProperty(prop);

                        try parseProperty(parser, writer, prop, propertyType);
                    },
                }
            },

            else => unreachable,
        }
    }
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

const Location = struct {
    line: u32,
    column: u32,

    pub fn format(value: @This(), fmt: []const u8, options: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.print("{}:{}", .{
            value.line,
            value.column,
        });
    }
};

const Token = struct {
    const Self = @This();
    type: TokenType,
    text: []const u8,
    location: Location,
};

const TokenIterator = struct {
    const Self = @This();

    data: []const u8,
    location: Location,
    peekedToken: ?Token, // only used for nextSkipWhitespace, peekNextWhitespace

    fn init(src: []const u8) Self {
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

    fn readUntil(self: *Self, types: anytype) !void {
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

    fn expect(self: *Self, _type: TokenType) !Token {
        var tok = try self.nextSkipWhitespace();
        if (tok) |t| {
            if (t.type != _type)
                return error.UnexpectedToken;
            return t;
        } else {
            return error.UnexpectedEndOfStream;
        }
    }

    fn expectOneOf(self: *Self, comptime types: anytype) !Token {
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

    fn peekNextWhitespace(self: *Self) !?Token {
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

// TODO: Codesmell, merge with libdunstblick
fn writeVarUInt(stream: anytype, value: u32) !void {
    var buf: [5]u8 = undefined;

    var maxidx: usize = 4;

    comptime var n: usize = 0;
    inline while (n < 5) : (n += 1) {
        const chr = &buf[4 - n];
        chr.* = @truncate(u8, (value >> (7 * n)) & 0x7F);
        if (chr.* != 0)
            maxidx = 4 - n;
        if (n > 0)
            chr.* |= 0x80;
    }

    std.debug.assert(maxidx < 5);
    try stream.writeAll(buf[maxidx..]);
}

// TODO: Codesmell, merge with libdunstblick
fn writeVarSInt(stream: anytype, value: i32) !void {
    try writeVarUInt(stream, ZigZagInt.encode(value));
}

// TODO: Codesmell, merge with libdunstblick
const ZigZagInt = struct {
    fn encode(n: i32) u32 {
        const v = (n << 1) ^ (n >> 31);
        return @bitCast(u32, v);
    }
    fn decode(u: u32) i32 {
        const n = @bitCast(i32, u);
        return (n << 1) ^ (n >> 31);
    }
};

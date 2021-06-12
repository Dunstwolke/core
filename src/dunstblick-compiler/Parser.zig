const std = @import("std");

const string_luts = @import("dunstblick-protocol").layout_format;
const enums = @import("dunstblick-protocol");

const Tokenizer = @import("Tokenizer.zig");
const ErrorCollection = @import("ErrorCollection.zig");
const Database = @import("Database.zig");
const Token = Tokenizer.Token;

const Parser = @This();

allocator: *std.mem.Allocator,
database: *Database,
errors: *ErrorCollection,
tokens: *Tokenizer,

fn widgetFromName(name: []const u8) ?enums.WidgetType {
    for (string_luts.widget_types) |tup| {
        if (std.mem.eql(u8, tup.widget, name))
            return tup.type;
    }
    return null;
}

fn propertyFromName(name: []const u8) ?enums.Property {
    for (string_luts.properties) |tup| {
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
    for (string_luts.properties) |v| {
        if (v.value == prop)
            return v.type;
    }
    unreachable;
}

pub fn parseFile(parser: Parser, writer: anytype) !void {
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

fn parseID(parser: Parser, writer: anytype, functionName: []const u8, entry: Database.Entry) !void {
    var resource = parser.tokens.expect(.identifier) catch {
        try parser.errors.add(parser.tokens.location, "Expected identifier.", .{});
        try parser.tokens.readUntil(.{.semiColon});
        return;
    };
    if (!std.mem.eql(u8, resource.text, functionName)) {
        try parser.errors.add(
            parser.tokens.location,
            "Expected {s}, found '{s}'.",
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

            const id_or_null = try parser.database.get(entry, name);
            if (id_or_null) |val| {
                break :blk val;
            } else {
                try parser.errors.add(parser.tokens.location, "Unkown {s} alias '{s}'", .{ functionName, name });
                break :blk @as(u32, 0);
            }
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

                try parseID(parser, writer, "bind", .property);

                return;
            }
        }
    }

    try writer.writeByte(@enumToInt(property));

    switch (propertyType) {
        // .none

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

        .resource => try parseID(parser, writer, "resource", .resource),

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
            const SizeEntry = union(enums.ColumnSizeType) {
                auto: void,
                expand: void,
                absolute: u32,
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
                            .absolute = try tokenToUnsignedInteger(item),
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

            // size list is packed as dense as posssible. each byte contains up to 4
            // size entries
            {
                var i: usize = 0;
                while (i < list.items.len) : (i += 4) {
                    var value: u8 = 0;

                    var j: usize = 0;
                    while (j < std.math.min(4, list.items.len - i)) : (j += 1) {
                        value |= @as(u8, @enumToInt(@as(enums.ColumnSizeType, list.items[i + j]))) << @intCast(u3, 2 * j);
                    }

                    try writer.writeByte(value);
                }
            }

            for (list.items) |item| {
                switch (item) {
                    .absolute => |v| try writeVarUInt(writer, v),
                    .percentage => |v| try writer.writeByte(@as(u8, v) | 0x80), // TODO: WTF?!
                    else => {},
                }
            }
        },

        .object => try parseID(parser, writer, "object", .object),

        .objectlist => {
            unreachable;
        },

        .event => try parseID(parser, writer, "callback", .event),

        .name => try parseID(parser, writer, "widget", .widget),
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
            "Unkown widget type {s}",
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
                        "Unkown widget or property '{s}'",
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

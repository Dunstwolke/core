const std = @import("std");
const protocol = @import("dunstblick-protocol");

pub fn main() !u8 {
    var stdout = std.io.getStdOut();
    var writer = stdout.writer();

    try writer.writeAll("# Dunstblick Widgets\n");
    try writer.writeAll("\n");
    try writer.writeAll("Description of the Widgets available in [Dunstblick](../dunstblick.md)\n");
    try writer.writeAll("\n");
    try writer.writeAll("## Overview\n");
    try writer.writeAll("\n");
    try writer.writeAll("The following widgets are available in [Dunstblick](../dunstblick.md):\n");
    try writer.writeAll("\n");

    for (protocol.layout_format.widget_types) |widget| {
        try writer.print("- [{s}](#widget:{s})\n", .{
            widget.widget,
            @tagName(widget.type),
        });
    }
    try writer.writeAll("\n");
    try writer.writeAll("## Widgets\n");
    try writer.writeAll("\n");

    for (protocol.layout_format.widget_types) |widget| {
        try writer.print("<h3 id=\"widget:{s}\">{s}</h3>\n", .{
            @tagName(widget.type),
            widget.widget,
        });

        if (widget.description.len > 0) {
            try writer.writeAll(widget.description);
            try writer.writeAll("\n");
        } else {
            std.log.warn("Widget {s} is missing a description!", .{widget.widget});
            try writer.writeAll("This widget doesn't have any documentation at this moment.\n");
        }
        try writer.writeAll("\n");
        try writer.writeAll("**Properties:**\n");
        try writer.writeAll("\n");

        for (widget.properties) |property_id, i| {
            const property = getPropertyInfo(property_id);
            if (i > 0) {
                try writer.writeAll(", ");
            }
            try writer.print("[`{s}`](#property:{s})", .{
                property.property,
                @tagName(property.value),
            });
        }
        try writer.writeAll("\n");

        try writer.writeAll("\n");
    }

    try writer.writeAll("## Properties\n");
    try writer.writeAll("\n");

    for (protocol.layout_format.properties) |prop| {
        try writer.print("<h3 id=\"property:{s}\">{s}</h3>\n", .{
            @tagName(prop.value),
            prop.property,
        });

        if (prop.description.len > 0) {
            try writer.writeAll(prop.description);
            try writer.writeAll("\n");
        } else {
            std.log.warn("Property {s} is missing a description!", .{prop.property});
            try writer.writeAll("This property doesn't have any documentation at this moment.\n");
        }

        try writer.writeAll("\n");

        try writer.print("**Data Type:** `{s}`\n", .{@tagName(prop.type)});
        try writer.writeAll("\n");

        if (prop.type == .enumeration) {
            try writer.writeAll("**Possible Values:** ");
            for (prop.allowed_enums) |enum_id, i| {
                const enumeration = getEnumInfo(enum_id);
                if (i > 0) {
                    try writer.writeAll(", ");
                }
                try writer.print("`{s}`", .{enumeration.enumeration});
            }
        }

        try writer.writeAll("\n");
    }

    return 0;
}

fn getPropertyInfo(id: protocol.Property) protocol.layout_format.PropertyDescriptor {
    for (protocol.layout_format.properties) |prop| {
        if (prop.value == id)
            return prop;
    }
    @panic("Someone forget to add a property to the descriptor list!");
}

fn getEnumInfo(id: protocol.Enum) protocol.layout_format.EnumDescriptor {
    for (protocol.layout_format.enumerations) |enumerator| {
        if (enumerator.value == id)
            return enumerator;
    }
    @panic("Someone forget to add a enumeration to the descriptor list!");
}

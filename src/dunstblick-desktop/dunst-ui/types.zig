const std = @import("std");
const protocol = @import("dunstblick-protocol");

pub const ObjectList = std.ArrayList(protocol.ObjectID);
pub const SizeList = std.ArrayList(protocol.ColumnSizeDefinition);
pub const String = std.ArrayList(u8);

pub const Object = @import("Object.zig");
pub const Value = @import("value.zig").Value;

pub const udp = @import("udp.zig");

pub const tcp = struct {
    pub usingnamespace v1;

    pub const v1 = @import("tcp/v1.zig");
};

pub usingnamespace @import("data-types.zig");

pub const Decoder = @import("decoder.zig").Decoder;

pub const ZigZagInt = @import("zigzagint.zig");

pub const Encoder = @import("encoder.zig").Encoder;

pub fn makeEncoder(stream: anytype) Encoder(@TypeOf(stream)) {
    return Encoder(@TypeOf(stream)).init(stream);
}

pub fn beginDisplayCommandEncoding(stream: anytype, command: DisplayCommand) !Encoder(@TypeOf(stream)) {
    var enc = Encoder(@TypeOf(stream)).init(stream);
    try enc.writeByte(@enumToInt(command));
    return enc;
}

pub fn beginApplicationCommandEncoding(stream: anytype, command: ApplicationCommand) !Encoder(@TypeOf(stream)) {
    var enc = Encoder(@TypeOf(stream)).init(stream);
    try enc.writeByte(@enumToInt(command));
    return enc;
}

pub const DisplayCommand = enum(u8) {
    disconnect = 0, // (reason)
    uploadResource = 1, // (rid, kind, data)
    addOrUpdateObject = 2, // (obj)
    removeObject = 3, // (oid)
    setView = 4, // (rid)
    setRoot = 5, // (oid)
    setProperty = 6, // (oid, name, value) // "unsafe command", uses the serverside object type or fails of property
    clear = 7, // (oid, name)
    insertRange = 8, // (oid, name, index, count, value …) // manipulate lists
    removeRange = 9, // (oid, name, index, count) // manipulate lists
    moveRange = 10, // (oid, name, indexFrom, indexTo, count) // manipulate lists
    _,
};

pub const ApplicationCommand = enum(u8) {
    eventCallback = 1, // (cid)
    propertyChanged = 2, // (oid, name, type, value)
    _,
};

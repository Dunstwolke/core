pub const ResourceID = u32;
pub const ObjectID = u32;
pub const PropertyName = u32;
pub const EventID = u32;
pub const WidgetName = u32;

pub const ResourceKind = extern enum(c_int) {
    layout = 0,
    bitmap = 1,
    drawing = 2,
    _,
};

pub const Type = extern enum(c_int) {
    integer = 1,
    number = 2,
    string = 3,
    enumeration = 4,
    margins = 5,
    color = 6,
    size = 7,
    point = 8,
    resource = 9,
    boolean = 10,
    object = 12,
    objectlist = 13,
    _,
};

pub const ClientCapabilities = extern enum(c_int) {
    none = 0,
    mouse = 1,
    keyboard = 2,
    touch = 4,
    highdpi = 8,
    tiltable = 16,
    resizable = 32,
    req_accessibility = 64,
    _,
};

pub const DisconnectReason = extern enum(c_int) {
    quit = 0,
    shutdown = 1,
    timeout = 2,
    network_error = 3,
    invalid_data = 4,
    protocol_mismatch = 5,
    _,
};

pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Point = extern struct {
    x: i32,
    y: i32,
};

pub const Size = extern struct {
    w: u32,
    h: u32,
};

pub const Margins = extern struct {
    left: u32,
    top: u32,
    right: u32,
    bottom: u32,
};

// only required for the API
// const ValueStorage = extern union {
//     integer: i32,
//     enumeration: u8,
//     number: f32,
//     string: [*:0]const u8,
//     resource: ResourceID,
//     object: ObjectID,
//     color: Color,
//     size: Size,
//     point: Point,
//     margins: Margins,
//     boolean: bool,
// };

// pub const Value = extern struct {
//     type: Type,
//     value: ValueStorage,
// };

// Required for C api
// pub const Provider = @Type(.Opaque);
// pub const Connection = @Type(.Opaque);
// pub const Object = @Type(.Opaque);

// this is only necessary for the C binding
// pub const Error = extern enum(c_int) {
//     none = 0,
//     invalid_arg = 1,
//     network = 2,
//     invalid_type = 3,
//     argument_out_of_range = 4,
//     out_of_memory = 5,
//     resource_not_found = 6,
//     _,
// };

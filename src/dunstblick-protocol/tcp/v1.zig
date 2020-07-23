const types = @import("../data-types.zig");

pub const magic = [4]u8{ 0x21, 0x06, 0xc1, 0x62 };
pub const protocol_version: u16 = 1;

pub const ClientCapabilities = packed struct {
    mouse: bool = false,
    keyboard: bool = false,
    touch: bool = false,
    highdpi: bool = false,
    tiltable: bool = false,
    resizable: bool = false,
    req_accessibility: bool = false,
    padding: u25 = 0,
};

comptime {
    @import("std").debug.assert(@bitSizeOf(ClientCapabilities) == 32);
}

/// Protocol initiating message sent from the display client to
/// the UI provider.
pub const ConnectHeader = packed struct {

    // protocol header, must not be changed or reordered between
    // different protocol versions!
    magic: [4]u8 = magic,
    protocol_version: u16 = protocol_version,

    // data header
    name: [32]u8,
    password: [32]u8,
    capabilities: ClientCapabilities,
    screen_size_x: u16,
    screen_size_y: u16,
};

/// Response from the ui provider to the display client.
/// Is the direct answer to @ref TcpConnectHeader.
pub const ConnectResponse = packed struct {
    ///< is `1` if the connection was successful, otherwise `0`.
    success: u32,
    ///< Number of resources that should be transferred to the display client.
    resource_count: u32,
};

/// Followed after the @ref TcpConnectResponse, `resourceCount` descriptors
/// are transferred to the display client.
pub const ResourceDescriptor = packed struct {
    /// The unique resource identifier.
    id: types.ResourceID,
    /// The type of the resource.
    type: types.ResourceKind,
    /// Size of the resource in bytes.
    size: u32,
    /// Siphash of the resource data.
    /// Key used is
    hash: [8]u8,
};

/// Followed after the set of @ref TcpResourceDescriptor
/// the display client answers with the number of required resources.
pub const ResourceRequestHeader = packed struct {
    request_count: u32,
};

/// Sent `request_count` times by the display server after the
/// @ref TcpResourceRequestHeader.
pub const ResourceRequest = packed struct {
    id: types.ResourceID,
};

/// Sent after the last @ref TcpResourceRequest for each
/// requested resource. Each @ref TcpResourceHeader is followed by a
/// blob containing the resource itself.
pub const ResourceHeader = packed struct {
    ///< id of the resource
    id: types.ResourceID,
    ///< size of the transferred resource
    size: u32,
};

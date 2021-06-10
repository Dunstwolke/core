//! All data is encoded little-endian and uses utf-8 for strings.
//! Text fields are either used fully or will be padded with NUL characters.
//! The protocol is built on top of the `charm` library which is available in
//! - C: https://github.com/jedisct1/charm
//! - Zig: https://github.com/jedisct1/zig-charm
//!
//! When encryption will be enabled by `AuthenticationResult`:
//! Each message after `AuthenticationResult` will be followed by a 16 byte `tag`
//! and will be encrypted with `charm`.
//! This means the client might be required to cache the full message into RAM, but the 
//! display server is able to stream-encrypt data from a ROM.

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
    const assert = @import("std").debug.assert;

    assert(@bitSizeOf(ClientCapabilities) == 32);
    assert(@sizeOf(InitiateHandshake.Flags) == 2);
    assert(@sizeOf(AcknowledgeHandshake.Response) == 2);
    assert(@sizeOf(AuthenticationResult.Result) == 2);
}

/// Client → Server
/// This is the initial kick-off for the protocol.
pub const InitiateHandshake = extern struct {
    /// Protocol identifier
    magic: [4]u8 = magic,

    /// Protocol version, designates 
    protocol_version: u16 = protocol_version,

    /// Client nonce for cryptography. This is a randomly generated
    /// byte sequence which should be provided by a cryptographic RNG API.
    client_nonce: [16]u8,

    /// Connection flags
    flags: Flags,

    pub const Flags = packed struct { // u16
        /// Tells the server that we provide a user name for authentication.
        /// If a user name is provided, it might be used for distinct authentication.
        has_username: bool,

        /// Tells the server that we provide a password for authentication.
        /// If a user name is present, this can be distinct per user, but there
        /// can also be just a single password for a server.
        has_password: bool,

        padding: u14 = 0,
    };
};

/// Server → Client
/// This is sent in response to the `InitiateHandshake` message.
/// This message will be followed by `AuthenticationInfo` when successful.
pub const AcknowledgeHandshake = extern struct {
    pub const Response = packed struct {
        /// The server requires a username to be present, but the client didn't declare
        /// to provide one.
        requires_username: bool,

        /// The server requires a password to be present, but the client didn't declare
        /// to provide one.
        requires_password: bool,

        /// The server doesn't accept usernames, but the client wants to send one.
        rejects_username: bool,

        /// The server doesn't accept passwords, but the client wants to send one.
        rejects_password: bool,

        padding: u12 = 0,
    };

    response: Response,

    /// Server nonce for cryptography. This is a randomly generated
    /// byte sequence which should be provided by a cryptographic RNG API.
    /// If respone is not 0 for all bits, this is allowed to be garbage.
    server_nonce: [16]u8,
};

/// Client → Server
/// This provides the server with the information *who* is authenticating
/// and if they are who they tell they are.
/// This might be skipped if no username and password is present and the server
/// will just send the final authentication info
pub const AuthenticationInfo = extern struct {
    // if(InitiateHandshake.flags.has_username) {
    //     /// The user name
    //     username: [32]u8,
    // },

    // if(InitiateHandshake.flags.has_password) {
    //     /// `hash(client_nonce ++ server_nonce)`
    //     server_verification: [32]u8,
    // },
};

/// Server → Client
/// This will be either sent after `AcknowledgeHandshake` or `AuthenticationInfo`
/// and will notify the client about the success of the authentication.
pub const AuthenticationResult = extern struct {
    pub const Result = enum(u16) {
        /// The authentication was successful and the client is verified.
        success = 0,

        /// The provided user credentials are invalid or the user name is
        /// not known.
        invalid_credentials = 1,
    };

    result: Result,

    /// Connection flags
    flags: packed struct { // u16
        /// Tells the client that this connection will be encrypted after this package.
        /// No information is leaked until this point.
        /// Note that it might be possible that
        encrypted: bool,

        padding: u15 = 0,
    },
};

/// Client → Server
/// Sent after a successful `AuthenticationResult`. Will inform the server about
/// the client geometry and capabilities.
pub const ConnectHeader = extern struct {
    capabilities: ClientCapabilities,
    screen_width: u16,
    screen_height: u16,

    // This might be expanded later
};

/// Server → Client
/// Response to the `ConnectHeader` message. Informs the client about all resources
/// that are provided by the server.
pub const ConnectResponse = extern struct {
    /// Number of resources that should be transferred to the display client.
    resource_count: u32,
};

/// Server → Client
/// One descriptor for each resource.
/// Send `ConnectResponse.resource_count` times after a `ConnectResponse`.
pub const ConnectResponseItem = extern struct {
    /// The unique resource identifier.
    id: types.ResourceID,
    /// The type of the resource.
    type: types.ResourceKind,
    /// Size of the resource in bytes.
    size: u32,
    /// Hash of the resource data.
    /// Is computed by `std.hash.Fnv1a_64`.
    hash: ResourceHash,
};

/// Client → Server
/// Followed after the last `ConnectResponseItem`.
/// The client answers with the number of requested resources.
/// The server will then respond with `resource_count` instances of the `ResourceHeader`.
pub const ResourceRequest = extern struct {
    // resource_count: u32,
    // id: [resource_count]ResourceID,
};

/// Server → Client
/// Sent after `ResourceRequest` for each requested resource.
/// After all `ResourceHeader`s are sent, the protocol will switch over to 
/// a message-based approach, see `Message`.
pub const ResourceHeader = extern struct {
    // /// size of the transferred resource
    // size: u32,

    /// id of the resource
    id: types.ResourceID,

    // /// The payload of the resource
    // data: [size]u8,
};

/// Server → Client
/// Client → Server
/// This will be the wrapper for messages after the full handshake is done for both messages
/// from server to client as well as client to server.
pub const Message = extern struct {
    /// Length of the message in bytes
    length: u32,

    // /// `length` bytes that contain the message body. When encryption is enabled,
    // /// this data will be encrypted.
    // data: [length]u32,
};

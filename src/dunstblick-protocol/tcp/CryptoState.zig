//! The common state for `ClientStateMachine` and `ServerStateMachine`.

const std = @import("std");
const Charm = @import("charm").Charm;

const Self = @This();

pub const Tag = [Charm.tag_length]u8;
pub const Hash = [Charm.hash_length]u8;
pub const Key = [Charm.key_length]u8;
pub const Nonce = [Charm.nonce_length]u8;

const Mode = enum {
    not_started,
    client,
    server,
};

/// When this is not `.not_started`, both `client_nonce` and `server_nonce` are properly
/// set and the crypto provider is ready. 
mode: Mode = .not_started,

/// When this is `true`, the packages will be encrypted/decrypted with `charm`.
encryption_enabled: bool = false,

/// The cryptographic provider for the connection.
charm: Charm,

/// The client nonce is a random string generated on the startup of the system.
client_nonce: Nonce,

/// The client nonce is a random string generated on the startup of the system.
server_nonce: Nonce,

pub fn init() Self {
    var self = Self{
        .client_nonce = undefined,
        .server_nonce = undefined,
        .charm = undefined,
    };
    std.crypto.random.bytes(&self.client_nonce);
    std.crypto.random.bytes(&self.server_nonce);
    return self;
}

pub fn startServer(self: *Self, client_nonce: Nonce) void {
    self.client_nonce = client_nonce;
    return self.start(.server);
}

pub fn startClient(self: *Self, server_nonce: Nonce) void {
    self.server_nonce = server_nonce;
    return self.start(.client);
}

fn start(self: *Self, mode: Mode) void {
    std.debug.assert(mode != .not_started);
    _ = self.hash(&self.client_nonce);
    _ = self.hash(&self.server_nonce);
    self.mode = mode;
}

pub fn encrypt(self: *Self, data: []u8) Tag {
    std.debug.assert(self.mode != .not_started);
    return self.charm.encrypt(data);
}

pub fn decrypt(self: *Self, tag: Tag, data: []u8) Tag {
    std.debug.assert(self.mode != .not_started);
    self.charm.decrypt(data, tag);
}

pub fn hash(self: *Self, data: []const u8) Hash {
    std.debug.assert(self.mode != .not_started);
    return self.charm.hash(data);
}

pub fn hashPassword(password: []const u8, salt: []const u8) Key {
    var key: Key = undefined;
    std.crypto.pwhash.pbkdf2(
        &key,
        password,
        salt,
        1_000,
        std.crypto.auth.hmac.HmacSha1,
    ) catch unreachable;
    return key;
}

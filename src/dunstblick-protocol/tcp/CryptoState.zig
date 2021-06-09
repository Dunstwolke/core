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

pub fn start(self: *Self, key: Key, mode: Mode) Hash {
    std.debug.assert(mode != .not_started);

    self.charm = Charm.new(key, null);
    // feed the state some random data, so we
    // kill replayability with this and
    // make the same data look different each connection
    _ = self.charm.hash(&self.client_nonce);
    _ = self.charm.hash(&self.server_nonce);

    var auth_token_src: [32]u8 = undefined;
    std.mem.copy(u8, auth_token_src[0..16], &self.client_nonce);
    std.mem.copy(u8, auth_token_src[16..32], &self.server_nonce);
    const auth_token = self.charm.hash(&auth_token_src);
    self.mode = mode;
    return auth_token;
}

pub fn encrypt(self: *Self, data: []u8) Tag {
    std.debug.assert(self.mode != .not_started);
    return self.charm.encrypt(data);
}

pub fn decrypt(self: *Self, tag: Tag, data: []u8) error{InvalidData}!void {
    std.debug.assert(self.mode != .not_started);
    self.charm.decrypt(data, tag) catch return error.InvalidData;
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

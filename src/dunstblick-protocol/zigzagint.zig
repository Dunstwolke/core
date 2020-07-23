pub fn encode(n: i32) u32 {
    const v = (n << 1) ^ (n >> 31);
    return @bitCast(u32, v);
}

pub fn decode(u: u32) i32 {
    const n = @bitCast(i32, u);
    return (n << 1) ^ (n >> 31);
}

test "ZigZag" {
    const input = 42;
    std.debug.assert(encode(input) == 84);
    std.debug.assert(decode(84) == input);
}

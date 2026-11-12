#+build !js
package services

ws_sha1 :: proc(data: []u8) -> [20]u8 {
    h: [5]u32 = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0}
    msg_len := len(data)
    bit_len := u64(msg_len) * 8
    padded_len := ((msg_len + 9 + 63) / 64) * 64
    padded := make([]u8, padded_len)
    defer delete(padded)
    copy(padded, data)
    padded[msg_len] = 0x80
    for i in 0 ..< 8 {
        padded[padded_len - 1 - i] = u8(bit_len >> (8 * u32(i)))
    }
    w: [80]u32
    for chunk := 0; chunk < padded_len; chunk += 64 {
        for i in 0 ..< 16 {
            base := chunk + i * 4
            w[i] = u32(padded[base]) << 24 | u32(padded[base + 1]) << 16 |
                   u32(padded[base + 2]) << 8 | u32(padded[base + 3])
        }
        for i in 16 ..< 80 {
            v := w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16]
            w[i] = (v << 1) | (v >> 31)
        }
        a, b, c, d, e := h[0], h[1], h[2], h[3], h[4]
        for i in 0 ..< 80 {
            f, k: u32
            switch {
            case i < 20:
                f = (b & c) | ((~b) & d)
                k = 0x5A827999
            case i < 40:
                f = b ~ c ~ d
                k = 0x6ED9EBA1
            case i < 60:
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1BBCDC
            case:
                f = b ~ c ~ d
                k = 0xCA62C1D6
            }
            temp := ((a << 5) | (a >> 27)) + f + e + k + w[i]
            e = d
            d = c
            c = (b << 30) | (b >> 2)
            b = a
            a = temp
        }
        h[0] += a
        h[1] += b
        h[2] += c
        h[3] += d
        h[4] += e
    }
    digest: [20]u8
    for i in 0 ..< 5 {
        digest[i * 4] = u8(h[i] >> 24)
        digest[i * 4 + 1] = u8(h[i] >> 16)
        digest[i * 4 + 2] = u8(h[i] >> 8)
        digest[i * 4 + 3] = u8(h[i])
    }
    return digest
}

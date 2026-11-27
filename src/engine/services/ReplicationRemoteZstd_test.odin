#+build !js
package services

import "core:testing"

@(test)
replication_remote_zstd_roundtrip :: proc(t: ^testing.T) {
	payload := make([]u8, 32768)
	defer delete(payload)
	for &value, index in payload {
		value = u8(index / 128)
	}
	compressed, used := replication_remote_zstd_compress(16, payload, true)
	if !testing.expect(t, used, "repeated remote payload should use compression") {return}
	defer delete(compressed)
	testing.expect(t, len(compressed) < len(payload) / 8, "compression should substantially reduce repeated payloads")

	frame := make([]u8, 5 + len(compressed))
	defer delete(frame)
	frame[0], frame[1], frame[2], frame[3], frame[4] = \
		'K', 'R', 'P', u8(Replication_Protocol_Version), Replication_Kind_Remote_Zstd
	copy(frame[5:], compressed)
	expanded, ok := replication_remote_zstd_decompress(frame)
	if !testing.expect(t, ok, "valid remote frame should decompress") {return}
	defer delete(expanded)
	matching := len(expanded) == len(payload) + 5 && expanded[4] == 16
	if matching {
		for byte, i in payload {
			if expanded[i + 5] != byte {matching = false; break}
		}
	}
	testing.expect(t, matching, "decompressed remote frame should preserve every byte")
}

@(test)
replication_remote_zstd_rejects_malformed :: proc(t: ^testing.T) {
	payload := make([]u8, 32768)
	defer delete(payload)
	compressed, used := replication_remote_zstd_compress(16, payload, true)
	if !testing.expect(t, used, "compressed input required for malformed frame test") {return}
	defer delete(compressed)

	frame := make([]u8, 5 + len(compressed) + 1)
	defer delete(frame)
	frame[0], frame[1], frame[2], frame[3], frame[4] = \
		'K', 'R', 'P', u8(Replication_Protocol_Version), Replication_Kind_Remote_Zstd
	copy(frame[5:], compressed)
	original := frame[:len(frame) - 1]

	_, ok := replication_remote_zstd_decompress(original[:8])
	testing.expect(t, !ok, "truncated envelope must be rejected")
	_, ok = replication_remote_zstd_decompress(original[:len(original) - 1])
	testing.expect(t, !ok, "truncated zstd frame must be rejected")
	_, ok = replication_remote_zstd_decompress(frame)
	testing.expect(t, !ok, "trailing bytes must be rejected")

	frame[5] = Replication_Kind_Unreliable_Remote
	_, ok = replication_remote_zstd_decompress(original)
	testing.expect(t, !ok, "unreliable packet kind must be rejected")
	frame[5] = 16

	frame[6] += 1
	_, ok = replication_remote_zstd_decompress(original)
	testing.expect(t, !ok, "incorrect expanded length must be rejected")
	frame[6] -= 1

	frame[6], frame[7], frame[8], frame[9] = 255, 255, 255, 255
	_, ok = replication_remote_zstd_decompress(original)
	testing.expect(t, !ok, "oversized declared length must be rejected")
	copy(frame[5:10], compressed[:5])

	frame[10] = 0
	_, ok = replication_remote_zstd_decompress(original)
	testing.expect(t, !ok, "corrupted zstd magic must be rejected")
}

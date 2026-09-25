package main

import "core:fmt"
import services "../src/engine/services"
import target "../src/engine/target"

main :: proc() {
	map_bytes := []u8{1, 2, 3, 4, 5}
	region, ok := services.Payload_Region(services.Payload{
		mode = target.Mode.Server,
		address = "127.0.0.1",
		port = 34567,
		name = "RoundTrip",
		map_bytes = map_bytes,
	})
	assert(ok && len(region) > 0)

	parsed, parsed_ok := services.Payload_Parse_Region(region)
	assert(parsed_ok)
	assert(parsed.mode == target.Mode.Server)
	assert(parsed.address == "127.0.0.1")
	assert(parsed.port == 34567)
	assert(parsed.name == "RoundTrip")
	assert(len(parsed.map_bytes) == 5 && parsed.map_bytes[4] == 5)
	delete(region)

	client_region, client_ok := services.Payload_Region(services.Payload{
		mode = target.Mode.Client,
		address = "10.0.0.5",
		port = 23456,
	})
	assert(client_ok)
	client_parsed, client_parsed_ok := services.Payload_Parse_Region(client_region)
	assert(client_parsed_ok && client_parsed.mode == target.Mode.Client)
	assert(client_parsed.address == "10.0.0.5")
	assert(client_parsed.port == 23456)
	assert(len(client_parsed.map_bytes) == 0)
	delete(client_region)

	bad_version := make([]u8, 40)
	copy(bad_version, "KINEPAY1")
	bad_version[8] = 2
	_, bad_version_ok := services.Payload_Parse_Region(bad_version)
	assert(!bad_version_ok && len(bad_version) > 0)
	delete(bad_version)

	bad_magic := make([]u8, 40)
	copy(bad_magic, "KINEPAYX")
	_, bad_magic_ok := services.Payload_Parse_Region(bad_magic)
	assert(!bad_magic_ok && len(bad_magic) > 0)
	delete(bad_magic)

	_, short_ok := services.Payload_Parse_Region([]u8{0x4b})
	assert(!short_ok)

	template := []u8{0x00, 0x01, 0x02, 0xbb}
	built, b_ok := services.Payload_Append(template, services.Payload{
		mode = target.Mode.Server,
		address = "192.168.1.10",
		port = 4000,
		name = "Embedded Game",
		map_bytes = []u8{9, 8, 7},
	})
	assert(b_ok)
	full, f_ok := services.Payload_Read_Back(built)
	assert(f_ok)
	assert(full.mode == target.Mode.Server)
	assert(full.address == "192.168.1.10")
	assert(full.port == 4000)
	assert(full.name == "Embedded Game")
	assert(len(full.map_bytes) == 3 && full.map_bytes[0] == 9 && full.map_bytes[2] == 7)
	delete(built)

	no_map, nm_ok := services.Payload_Append(template, services.Payload{
		mode = target.Mode.Client,
		address = "127.0.0.1",
		port = 1234,
	})
	assert(nm_ok)
	no_map_read, nmr_ok := services.Payload_Read_Back(no_map)
	assert(nmr_ok && len(no_map_read.map_bytes) == 0)
	assert(no_map_read.port == 1234)
	delete(no_map)

	plain, p_ok := services.Payload_Read_Back(template)
	assert(!p_ok && len(template) > 0)

	fmt.println("PAYLOAD_ROUNDTRIP_SMOKE_PASSED")
}
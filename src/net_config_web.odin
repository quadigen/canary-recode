#+build js
package main

import "core:strconv"
import "core:strings"

foreign import "kinemium_net"

@(default_calling_convention = "c")
foreign kinemium_net {
	host_net_param :: proc(name: cstring, out: [^]u8, cap: i32) -> i32 ---
}

CONFIG_ADDRESS :: #config(KINE_ADDRESS, "")
CONFIG_PORT :: #config(KINE_PORT, 0)


web_query_param :: proc(name: string) -> string {
	c_name := strings.clone_to_cstring(name)
	defer delete(c_name)
	size := host_net_param(c_name, nil, 0)
	if size <= 0 {return ""}
	buffer := make([]u8, int(size))
	defer delete(buffer)
	got := host_net_param(c_name, raw_data(buffer), i32(size))
	if got < 0 {return ""}
	return strings.clone(string(buffer[:got]))
}

web_client_address :: proc() -> string {
	if value := web_query_param("address"); value != "" {return value}
	return CONFIG_ADDRESS
}

web_client_port :: proc() -> u16 {
	if value := web_query_param("port"); value != "" {
		if port, ok := strconv.parse_u64(value); ok {return u16(port)}
	}
	return u16(CONFIG_PORT)
}

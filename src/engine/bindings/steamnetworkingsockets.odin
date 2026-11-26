package kineffi


when ODIN_OS == .Windows {
	foreign import kine_gns_lib {"../../../vendor/build/lib/kine_networking.lib", "../../../vendor/build/lib/GameNetworkingSockets.lib"}
} else when #config(KINE_ANDROID, false) {
	foreign import kine_gns_lib "../../../build/android-native/lib/kine_networking.a"
} else when ODIN_OS == .Linux {
	foreign import kine_gns_lib {"../../../vendor/build/lib/kine_networking.a", "system:GameNetworkingSockets", "system:stdc++"}
} else {
	foreign import kine_gns_lib {"../../../vendor/build/lib/kine_networking.a", "system:GameNetworkingSockets", "system:c++"}
}

KineGnsHost :: rawptr
KineGnsEvent :: struct {
	type:      i32,
	peer:      u32,
	channel:   u8,
	reserved:  [3]u8,
	data:      [^]u8,
	data_size: u32,
}

@(default_calling_convention = "c")
foreign kine_gns_lib {
	Kine_Gns_Init :: proc() -> bool ---
	Kine_Gns_Kill :: proc() ---
	Kine_Gns_TimeMs :: proc() -> u32 ---
	Kine_Gns_GetSendRate :: proc(host: KineGnsHost) -> i32 ---
	Kine_Gns_SetSendRate :: proc(host: KineGnsHost, bytes_per_second: i32) -> bool ---
	Kine_Gns_CreateServer :: proc(address: cstring, port: u16, max_peers: i32) -> KineGnsHost ---
	Kine_Gns_CreateClient :: proc() -> KineGnsHost ---
	Kine_Gns_Connect :: proc(host: KineGnsHost, address: cstring, port: u16) -> u32 ---
	Kine_Gns_Poll :: proc(host: KineGnsHost, out_event: ^KineGnsEvent) -> bool ---
	Kine_Gns_Send :: proc(host: KineGnsHost, peer: u32, channel: u8, data: [^]u8, size: u32, reliable, unsequenced: bool) -> bool ---
	Kine_Gns_IsConnected :: proc(host: KineGnsHost, peer: u32) -> bool ---
	Kine_Gns_IsActive :: proc(host: KineGnsHost, peer: u32) -> bool ---
	Kine_Gns_Flush :: proc(host: KineGnsHost) ---
	Kine_Gns_Close :: proc(host: KineGnsHost, peer: u32, immediate: bool) ---
	Kine_Gns_Destroy :: proc(host: KineGnsHost) ---
}

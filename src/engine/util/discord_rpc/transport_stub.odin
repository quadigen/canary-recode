#+build js
package discord_rpc


Transport :: struct {}

@(private)
transport_open :: proc(t: ^Transport) -> bool {
	return false
}

@(private)
transport_close :: proc(t: ^Transport) {}

@(private)
transport_write :: proc(t: ^Transport, data: []byte) -> bool {
	return false
}

@(private)
transport_read :: proc(t: ^Transport, buf: []byte, timeout_ms: int) -> (n: int, st: Read_Status) {
	return 0, .Closed
}

@(private)
transport_pid :: proc() -> u32 {
	return 0
}

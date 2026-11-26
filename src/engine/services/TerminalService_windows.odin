package services

import terminal "../terminal"

terminal_windows_create :: proc(directory: string) -> ^Terminal_Session {
	native := terminal.Create(directory)
	if native == nil {return nil}
	session := new(Terminal_Session)
	session.native = native
	session.running = true
	return session
}

terminal_windows_poll :: proc(session: ^Terminal_Session) -> bool {
	exited, code := terminal.Poll(cast(^terminal.Session)session.native)
	if exited {session.exit_code = code}
	return exited
}

terminal_windows_write :: proc(session: ^Terminal_Session, data: []u8) -> int {
	return terminal.Write(cast(^terminal.Session)session.native, data)
}

terminal_windows_read :: proc(session: ^Terminal_Session, data: []u8) -> int {
	return terminal.Read(cast(^terminal.Session)session.native, data)
}

terminal_windows_destroy :: proc(session: ^Terminal_Session) {
	terminal.Destroy(cast(^terminal.Session)session.native)
	session.native = nil
}

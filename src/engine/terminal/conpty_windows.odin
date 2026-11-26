package terminal

import "core:crypto"
import "core:fmt"
import win "core:sys/windows"

Create_Pseudo_Console :: #type proc "system" (
	_: win.COORD,
	_: win.HANDLE,
	_: win.HANDLE,
	_: u32,
	_: ^win.HANDLE,
) -> i32
Close_Pseudo_Console :: #type proc "system" (_: win.HANDLE)
Initialize_Attributes :: #type proc "system" (_: rawptr, _: u32, _: u32, _: ^uintptr) -> win.BOOL
Update_Attribute :: #type proc "system" (
	_: rawptr,
	_: u32,
	_: uintptr,
	_: rawptr,
	_: uintptr,
	_: rawptr,
	_: ^uintptr,
) -> win.BOOL
Delete_Attributes :: #type proc "system" (_: rawptr)

Startup_Info :: struct {
	info:       win.STARTUPINFOW,
	attributes: rawptr,
}

Session :: struct {
	process:       win.HANDLE,
	console:       win.HANDLE,
	input:         win.HANDLE,
	output:        win.HANDLE,
	close_console: Close_Pseudo_Console,
}

close_handle :: proc(handle: win.HANDLE) {
	if handle != nil && handle != win.INVALID_HANDLE {_ = win.CloseHandle(handle)}
}

Create :: proc(directory: string) -> ^Session {
	kernel := win.GetModuleHandleW("kernel32.dll")
	if kernel == nil {return nil}
	create_console := cast(Create_Pseudo_Console)win.GetProcAddress(kernel, "CreatePseudoConsole")
	close_console := cast(Close_Pseudo_Console)win.GetProcAddress(kernel, "ClosePseudoConsole")
	initialize := cast(Initialize_Attributes)win.GetProcAddress(
		kernel,
		"InitializeProcThreadAttributeList",
	)
	update := cast(Update_Attribute)win.GetProcAddress(kernel, "UpdateProcThreadAttribute")
	destroy := cast(Delete_Attributes)win.GetProcAddress(kernel, "DeleteProcThreadAttributeList")
	if create_console == nil ||
	   close_console == nil ||
	   initialize == nil ||
	   update == nil ||
	   destroy == nil {
		return nil
	}

	random: [16]u8
	crypto.rand_bytes(random[:])
	pipe_name := win.utf8_to_wstring(
		fmt.tprintf("\\\\.\\pipe\\kinemium-terminal-%x-%x", win.GetCurrentProcessId(), random),
	)
	if pipe_name == nil {return nil}
	input := win.CreateNamedPipeW(
		pipe_name,
		win.PIPE_ACCESS_OUTBOUND | win.FILE_FLAG_FIRST_PIPE_INSTANCE,
		win.PIPE_TYPE_BYTE | win.PIPE_REJECT_REMOTE_CLIENTS | 1,
		1,
		65536,
		0,
		0,
		nil,
	)
	if input == win.INVALID_HANDLE {return nil}
	output: win.HANDLE
	console: win.HANDLE
	success := false
	defer {
		if !success {
			close_handle(input)
			close_handle(output)
			if console != nil {close_console(console)}
		}
	}
	pty_input := win.CreateFileW(pipe_name, win.GENERIC_READ, 0, nil, win.OPEN_EXISTING, 0, nil)
	if pty_input == win.INVALID_HANDLE {return nil}
	defer close_handle(pty_input)
	if !win.ConnectNamedPipe(input, nil) && win.GetLastError() != 535 {return nil}

	pty_output: win.HANDLE
	if !win.CreatePipe(&output, &pty_output, nil, 65536) {return nil}
	defer close_handle(pty_output)
	if create_console(win.COORD{120, 40}, pty_input, pty_output, 0, &console) < 0 {return nil}

	bytes: uintptr
	_ = initialize(nil, 1, 0, &bytes)
	if bytes == 0 {return nil}
	heap := win.GetProcessHeap()
	attributes := win.HeapAlloc(heap, 0, uint(bytes))
	if attributes == nil {return nil}
	defer _ = win.HeapFree(heap, 0, attributes)
	if !initialize(attributes, 1, 0, &bytes) {return nil}
	defer destroy(attributes)
	if !update(
		attributes,
		0,
		0x00020016,
		rawptr(console),
		size_of(win.HANDLE),
		nil,
		nil,
	) {return nil}

	executable: [32768]u16
	length := int(win.GetSystemDirectoryW(&executable[0], u32(len(executable))))
	suffix := [?]u16{'\\', 'c', 'm', 'd', '.', 'e', 'x', 'e', 0}
	if length <= 0 || length + len(suffix) > len(executable) {return nil}
	copy(executable[length:], suffix[:])
	command: [32]u16
	command_line := win.utf8_to_wstring(command[:], "cmd.exe /D /Q")
	working_directory: win.LPCWSTR
	if directory != "" {
		working_directory = win.utf8_to_wstring(directory)
		if working_directory == nil {return nil}
	}
	startup := Startup_Info{}
	startup.info.cb = size_of(Startup_Info)
	startup.attributes = attributes
	process: win.PROCESS_INFORMATION
	if !win.CreateProcessW(
		win.LPCWSTR(&executable[0]),
		command_line,
		nil,
		nil,
		false,
		win.EXTENDED_STARTUPINFO_PRESENT,
		nil,
		working_directory,
		&startup.info,
		&process,
	) {return nil}
	close_handle(process.hThread)

	session := new(Session)
	session^ = Session{process.hProcess, console, input, output, close_console}
	success = true
	return session
}

Poll :: proc(session: ^Session) -> (exited: bool, code: i32) {
	if win.WaitForSingleObject(session.process, 0) != win.WAIT_OBJECT_0 {return false, 0}
	exit_code: u32
	_ = win.GetExitCodeProcess(session.process, &exit_code)
	return true, i32(exit_code)
}

Write :: proc(session: ^Session, data: []u8) -> int {
	if len(data) == 0 {return 0}
	written: u32
	_ = win.WriteFile(session.input, raw_data(data), u32(len(data)), &written, nil)
	return int(written)
}

Read :: proc(session: ^Session, data: []u8) -> int {
	available: u32
	if !win.PeekNamedPipe(session.output, nil, 0, nil, &available, nil) ||
	   available == 0 {return 0}
	read: u32
	_ = win.ReadFile(session.output, raw_data(data), min(available, u32(len(data))), &read, nil)
	return int(read)
}

Destroy :: proc(session: ^Session) {
	if session == nil {return}
	if win.WaitForSingleObject(session.process, 0) != win.WAIT_OBJECT_0 {
		_ = win.TerminateProcess(session.process, 1)
	}
	close_handle(session.input)
	close_handle(session.output)
	session.close_console(session.console)
	_ = win.WaitForSingleObject(session.process, 1000)
	close_handle(session.process)
	free(session)
}

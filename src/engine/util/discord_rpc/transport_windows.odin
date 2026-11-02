#+build windows
package discord_rpc

import "core:fmt"
import "core:mem"
import win "core:sys/windows"
import "core:time"

foreign import kernel32 "system:Kernel32.lib"

@(private = "file")
@(default_calling_convention = "system")
foreign kernel32 {
	PeekNamedPipe :: proc(hNamedPipe: win.HANDLE, lpBuffer: rawptr, nBufferSize: win.DWORD, lpBytesRead: ^win.DWORD, lpTotalBytesAvail: ^win.DWORD, lpBytesLeftThisMessage: ^win.DWORD) -> win.BOOL ---
}

Transport :: struct {
	handle: win.HANDLE,
	open:   bool,
}


@(private)
transport_open :: proc(t: ^Transport) -> bool {
	for i in 0 ..< MAX_PIPES {
		name_buf: [64]u8
		path := fmt.bprintf(name_buf[:], `\\?\pipe\discord-ipc-%d`, i)

		scratch: [256]byte
		arena: mem.Arena
		mem.arena_init(&arena, scratch[:])
		wpath := win.utf8_to_wstring(path, mem.arena_allocator(&arena))

		h := win.CreateFileW(
			wpath,
			win.GENERIC_READ | win.GENERIC_WRITE,
			0,
			nil,
			win.OPEN_EXISTING,
			0,
			nil,
		)
		if h == win.INVALID_HANDLE_VALUE {
			continue
		}
		t.handle = h
		t.open = true
		return true
	}
	return false
}

@(private)
transport_close :: proc(t: ^Transport) {
	if t.open {
		win.CloseHandle(t.handle)
	}
	t^ = {}
}

@(private)
transport_write :: proc(t: ^Transport, data: []byte) -> bool {
	if !t.open {
		return false
	}
	sent := 0
	for sent < len(data) {
		written: win.DWORD
		if !win.WriteFile(t.handle, &data[sent], win.DWORD(len(data) - sent), &written, nil) {
			return false
		}
		sent += int(written)
	}
	return true
}


@(private)
transport_read :: proc(t: ^Transport, buf: []byte, timeout_ms: int) -> (n: int, st: Read_Status) {
	if !t.open {
		return 0, .Closed
	}
	start := time.tick_now()
	for {
		avail: win.DWORD
		if !PeekNamedPipe(t.handle, nil, 0, nil, &avail, nil) {
			return 0, .Closed
		}
		if avail > 0 {
			want := win.DWORD(min(int(avail), len(buf)))
			got: win.DWORD
			if !win.ReadFile(t.handle, raw_data(buf), want, &got, nil) {
				return 0, .Closed
			}
			return int(got), .Ok
		}
		if timeout_ms >= 0 &&
		   time.tick_since(start) >= time.Duration(timeout_ms) * time.Millisecond {
			return 0, .Timeout
		}
		time.sleep(time.Millisecond)
	}
}

@(private)
transport_pid :: proc() -> u32 {
	return u32(win.GetCurrentProcessId())
}

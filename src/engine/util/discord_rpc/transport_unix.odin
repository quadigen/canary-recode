#+build linux, darwin
package discord_rpc

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:strings"

foreign import clib "system:c"

@(private = "file")
AF_UNIX :: 1
@(private = "file")
SOCK_STREAM :: 1
@(private = "file")
POLLIN :: 0x001
@(private = "file")
EINTR :: 4

when ODIN_OS == .Linux {
	@(private = "file")
	MSG_NOSIGNAL :: 0x4000
	@(private = "file")
	Sockaddr_Un :: struct {
		family: u16,
		path:   [108]u8,
	}
} else {

	@(private = "file")
	MSG_NOSIGNAL :: 0
	@(private = "file")
	Sockaddr_Un :: struct {
		len:    u8,
		family: u8,
		path:   [104]u8,
	}
}

@(private = "file")
Pollfd :: struct {
	fd:      c.int,
	events:  c.short,
	revents: c.short,
}

@(private = "file")
@(default_calling_convention = "c")
foreign clib {
	@(link_name = "socket")
	c_socket :: proc(domain, kind, protocol: c.int) -> c.int ---
	@(link_name = "connect")
	c_connect :: proc(fd: c.int, addr: rawptr, len: u32) -> c.int ---
	@(link_name = "setsockopt")
	c_setsockopt :: proc(fd, level, name: c.int, val: rawptr, len: u32) -> c.int ---
	@(link_name = "send")
	c_send :: proc(fd: c.int, buf: rawptr, n: uint, flags: c.int) -> int ---
	@(link_name = "read")
	c_read :: proc(fd: c.int, buf: rawptr, n: uint) -> int ---
	@(link_name = "close")
	c_close :: proc(fd: c.int) -> c.int ---
	@(link_name = "poll")
	c_poll :: proc(fds: ^Pollfd, nfds: c.ulong, timeout: c.int) -> c.int ---
	@(link_name = "getpid")
	c_getpid :: proc() -> c.int ---
	@(link_name = "getenv")
	c_getenv :: proc(name: cstring) -> cstring ---
}

Transport :: struct {
	fd:   c.int,
	open: bool,
}


@(private)
transport_open :: proc(t: ^Transport) -> bool {
	env_names := [?]cstring{"XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"}
	sub_dirs := [?]string {
		"",
		"app/com.discordapp.Discord",
		"app/com.discordapp.DiscordCanary",
		"snap.discord",
		"snap.discord-canary",
	}
	for name in env_names {
		dir := c_getenv(name)
		if dir == nil {
			continue
		}
		base := strings.trim_right(string(dir), "/")
		if len(base) == 0 {
			continue
		}
		for sub in sub_dirs {
			if try_dir(t, base, sub) {
				return true
			}
		}
	}
	return try_dir(t, "/tmp", "")
}

@(private = "file")
try_dir :: proc(t: ^Transport, base, sub: string) -> bool {
	for i in 0 ..< MAX_PIPES {
		buf: [256]u8
		path: string
		if len(sub) > 0 {
			path = fmt.bprintf(buf[:], "%s/%s/discord-ipc-%d", base, sub, i)
		} else {
			path = fmt.bprintf(buf[:], "%s/discord-ipc-%d", base, i)
		}
		if try_connect(t, path) {
			return true
		}
	}
	return false
}

@(private = "file")
try_connect :: proc(t: ^Transport, path: string) -> bool {
	addr: Sockaddr_Un
	if len(path) >= len(addr.path) {
		return false
	}
	fd := c_socket(AF_UNIX, SOCK_STREAM, 0)
	if fd < 0 {
		return false
	}
	when ODIN_OS == .Darwin {
		one: c.int = 1
		c_setsockopt(fd, 0xffff, 0x1022, &one, size_of(c.int))
		addr.len = size_of(Sockaddr_Un)
	}
	addr.family = AF_UNIX
	copy(addr.path[:], path)

	if c_connect(fd, &addr, size_of(Sockaddr_Un)) != 0 {
		c_close(fd)
		return false
	}
	t.fd = fd
	t.open = true
	return true
}

@(private)
transport_close :: proc(t: ^Transport) {
	if t.open {
		c_close(t.fd)
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
		n := c_send(t.fd, &data[sent], uint(len(data) - sent), MSG_NOSIGNAL)
		if n < 0 {
			if libc.errno()^ == EINTR {
				continue
			}
			return false
		}
		sent += n
	}
	return true
}


@(private)
transport_read :: proc(t: ^Transport, buf: []byte, timeout_ms: int) -> (n: int, st: Read_Status) {
	if !t.open {
		return 0, .Closed
	}
	pfd := Pollfd {
		fd     = t.fd,
		events = POLLIN,
	}
	for {
		r := c_poll(&pfd, 1, c.int(timeout_ms))
		if r < 0 {
			if libc.errno()^ == EINTR {
				continue
			}
			return 0, .Closed
		}
		if r == 0 {
			return 0, .Timeout
		}

		got := c_read(t.fd, raw_data(buf), uint(len(buf)))
		if got < 0 {
			if libc.errno()^ == EINTR {
				continue
			}
			return 0, .Closed
		}
		if got == 0 {
			return 0, .Closed
		}
		return got, .Ok
	}
}

@(private)
transport_pid :: proc() -> u32 {
	return u32(c_getpid())
}

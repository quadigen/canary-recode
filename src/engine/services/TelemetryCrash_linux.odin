#+build linux
#+build !js

package services

import "core:os"
import "core:strings"
import "core:sys/linux"

import fsutil "../fsutil"

telemetry_crash_fd: linux.Fd = -1
telemetry_crash_installed: bool
telemetry_crash_pending: string
telemetry_crash_previous: [5]linux.Sig_Action
telemetry_crash_stack: [64 * 1024]u8
telemetry_crash_stack_active: bool

telemetry_crash_signals := [5]linux.Signal{.SIGSEGV, .SIGBUS, .SIGILL, .SIGABRT, .SIGFPE}

telemetry_signal_callback :: proc "c" (sig: linux.Signal, info: ^linux.Sig_Info, ctx: rawptr) {
	if telemetry_crash_fd >= 0 {
		#partial switch sig {
		case .SIGSEGV:
			_, _ = linux.write(telemetry_crash_fd, transmute([]u8)string("SIGSEGV"))
		case .SIGBUS:
			_, _ = linux.write(telemetry_crash_fd, transmute([]u8)string("SIGBUS"))
		case .SIGILL:
			_, _ = linux.write(telemetry_crash_fd, transmute([]u8)string("SIGILL"))
		case .SIGABRT:
			_, _ = linux.write(telemetry_crash_fd, transmute([]u8)string("SIGABRT"))
		case .SIGFPE:
			_, _ = linux.write(telemetry_crash_fd, transmute([]u8)string("SIGFPE"))
		case:
		}
		_ = linux.fsync(telemetry_crash_fd)
	}
	default_action := linux.Sig_Action {
		special = .SIG_DFL,
	}
	_ = linux.rt_sigaction(sig, &default_action, nil)
	_ = linux.tgkill(linux.getpid(), linux.gettid(), sig)
}

Telemetry_Crash_Install :: proc() {
	if telemetry_crash_installed {return}
	data_dir, dir_err := os.user_data_dir(context.allocator)
	if dir_err != nil {return}
	defer delete(data_dir)
	dir, path_err := os.join_path({data_dir, "Kinemium"}, context.allocator)
	if path_err != nil {return}
	defer delete(dir)
	if fsutil.Make_Directory_All(dir) != nil && !os.is_directory(dir) {return}
	path, file_err := os.join_path({dir, "crash-signal.txt"}, context.allocator)
	if file_err != nil {return}
	defer delete(path)

	if len(telemetry_crash_pending) == 0 {
		if previous, err := os.read_entire_file_from_path(path, context.allocator); err == nil {
			switch strings.trim_space(string(previous)) {
			case "SIGSEGV":
				telemetry_crash_pending = "NATIVE_SIGSEGV"
			case "SIGBUS":
				telemetry_crash_pending = "NATIVE_SIGBUS"
			case "SIGILL":
				telemetry_crash_pending = "NATIVE_SIGILL"
			case "SIGABRT":
				telemetry_crash_pending = "NATIVE_SIGABRT"
			case "SIGFPE":
				telemetry_crash_pending = "NATIVE_SIGFPE"
			}
			delete(previous)
		}
	}

	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	fd, open_err := linux.open(cpath, {.WRONLY, .CREAT, .TRUNC, .CLOEXEC}, {.IRUSR, .IWUSR})
	if open_err != .NONE {return}
	telemetry_crash_fd = fd

	stack := linux.Sig_Stack {
		sp   = &telemetry_crash_stack[0],
		size = len(telemetry_crash_stack),
	}
	telemetry_crash_stack_active = linux.sigaltstack(&stack, nil) == .NONE
	action := linux.Sig_Action {
		sigaction = telemetry_signal_callback,
		flags     = {.SIGINFO, .RESETHAND},
	}
	if telemetry_crash_stack_active {action.flags += {.ONSTACK}}
	installed: int
	for sig in telemetry_crash_signals {
		if linux.rt_sigaction(sig, &action, &telemetry_crash_previous[installed]) != .NONE {
			break
		}
		installed += 1
	}
	if installed != len(telemetry_crash_signals) {
		for i in 0 ..< installed {
			_ = linux.rt_sigaction(telemetry_crash_signals[i], &telemetry_crash_previous[i], nil)
		}
		if telemetry_crash_stack_active {
			old_stack := linux.Sig_Stack {
				flags = {.DISABLE},
			}
			_ = linux.sigaltstack(&old_stack, nil)
		}
		telemetry_crash_stack_active = false
		_ = linux.close(telemetry_crash_fd)
		telemetry_crash_fd = -1
		return
	}
	telemetry_crash_installed = true
}

Telemetry_Crash_Read_Pending :: proc() -> string {
	result := telemetry_crash_pending
	telemetry_crash_pending = ""
	return result
}

Telemetry_Crash_Uninstall :: proc() {
	if !telemetry_crash_installed {return}
	for sig, i in telemetry_crash_signals {
		_ = linux.rt_sigaction(sig, &telemetry_crash_previous[i], nil)
	}
	telemetry_crash_installed = false
	if telemetry_crash_stack_active {
		stack := linux.Sig_Stack {
			flags = {.DISABLE},
		}
		_ = linux.sigaltstack(&stack, nil)
		telemetry_crash_stack_active = false
	}
	if telemetry_crash_fd >= 0 {
		_ = linux.close(telemetry_crash_fd)
		telemetry_crash_fd = -1
	}
}

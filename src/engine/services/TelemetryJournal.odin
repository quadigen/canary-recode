#+build !js

package services

import "base:runtime"
import "core:os"
import "core:strings"
import "core:sync"

import fsutil "../fsutil"
import target "../target"

telemetry_journal_file: ^os.File
telemetry_journal_path: string
telemetry_journal_pending_path: string
telemetry_journal_size: int
telemetry_journal_mu: sync.Mutex

Telemetry_Journal_Start_At :: proc(path: string) -> string {
	sync.mutex_lock(&telemetry_journal_mu)
	defer sync.mutex_unlock(&telemetry_journal_mu)
	if telemetry_journal_file != nil {return ""}
	allocator := runtime.heap_allocator()
	telemetry_journal_path = strings.clone(path, allocator)
	telemetry_journal_pending_path = strings.concatenate({path, ".pending"}, allocator)
	if !os.exists(telemetry_journal_pending_path) && os.is_file(path) {
		_ = os.rename(path, telemetry_journal_pending_path)
	}
	previous := ""
	if bytes, read_err := os.read_entire_file_from_path(telemetry_journal_pending_path, allocator);
	   read_err == nil {
		if len(bytes) > 0 && len(bytes) <= TELEMETRY_MAX_LOG_BYTES {
			previous = strings.clone(strings.trim_space(string(bytes)), allocator)
		}
		delete(bytes, allocator)
	}
	file, open_err := os.open(path, {.Write, .Create, .Trunc}, {.Read_User, .Write_User})
	if open_err == nil {
		telemetry_journal_file = file
		telemetry_journal_size = 0
	}
	return previous
}

Telemetry_Journal_Start :: proc() -> string {
	if telemetry_journal_file != nil {return ""}
	allocator := runtime.heap_allocator()
	data_dir, dir_err := os.user_data_dir(allocator)
	if dir_err != nil {return ""}
	defer delete(data_dir, allocator)
	dir, join_err := os.join_path({data_dir, "Kinemium"}, allocator)
	if join_err != nil {return ""}
	defer delete(dir, allocator)
	if !os.is_directory(dir) && fsutil.Make_Directory_All(dir) != nil {return ""}
	name := strings.concatenate({"telemetry-session-", target.name(), ".log"}, allocator)
	defer delete(name, allocator)
	path, path_err := os.join_path({dir, name}, allocator)
	if path_err != nil {return ""}
	defer delete(path, allocator)
	return Telemetry_Journal_Start_At(path)
}

Telemetry_Journal_Append :: proc(line, last_half: string) {
	sync.mutex_lock(&telemetry_journal_mu)
	defer sync.mutex_unlock(&telemetry_journal_mu)
	if telemetry_journal_file == nil {return}
	size := len(line) + 1
	if telemetry_journal_size + size > TELEMETRY_MAX_LOG_BYTES {
		_ = os.close(telemetry_journal_file)
		telemetry_journal_file = nil
		if os.write_entire_file_from_string(
			   telemetry_journal_path,
			   last_half,
			   {.Read_User, .Write_User},
		   ) !=
		   nil {return}
		file, err := os.open(telemetry_journal_path, {.Write, .Append})
		if err != nil {return}
		telemetry_journal_file = file
		telemetry_journal_size = len(last_half)
		return
	}
	n, err := os.write(telemetry_journal_file, transmute([]u8)line)
	if err != nil || n != len(line) {return}
	_, _ = os.write(telemetry_journal_file, transmute([]u8)string("\n"))
	telemetry_journal_size += size
}

Telemetry_Journal_Confirm_Recovery :: proc() {
	sync.mutex_lock(&telemetry_journal_mu)
	defer sync.mutex_unlock(&telemetry_journal_mu)
	if telemetry_journal_pending_path != "" {
		_ = os.remove(telemetry_journal_pending_path)
	}
}

Telemetry_Journal_Stop :: proc(clear: bool, clear_pending: bool = false) {
	sync.mutex_lock(&telemetry_journal_mu)
	defer sync.mutex_unlock(&telemetry_journal_mu)
	if telemetry_journal_file != nil {
		_ = os.close(telemetry_journal_file)
		telemetry_journal_file = nil
	}
	if telemetry_journal_path != "" {
		if clear {_ = os.remove(telemetry_journal_path)}
		delete(telemetry_journal_path, runtime.heap_allocator())
		telemetry_journal_path = ""
	}
	if telemetry_journal_pending_path != "" {
		if clear_pending {_ = os.remove(telemetry_journal_pending_path)}
		delete(telemetry_journal_pending_path, runtime.heap_allocator())
		telemetry_journal_pending_path = ""
	}
	telemetry_journal_size = 0
}

package fsutil

import "core:os"
import "core:strings"

Make_Directory_All :: proc(path: string) -> os.Error {
	if path == "" {
		return .Invalid_Path
	}
	if os.is_directory(path) {
		return nil
	}
	when #config(KINE_ANDROID, false) {
		return mkdir_all_direct(path)
	} else {
		err := os.make_directory_all(path)
		if err == .Exist && os.is_directory(path) {
			err = nil
		}
		return err
	}
}

Exists :: proc(path: string) -> bool {
	return os.exists(path)
}

Is_File :: proc(path: string) -> bool {
	return os.is_file(path)
}

Is_Directory :: proc(path: string) -> bool {
	return os.is_directory(path)
}

Make_Directory :: proc(path: string) -> os.Error {
	return os.make_directory(path)
}

Remove :: proc(path: string) -> os.Error {
	return os.remove(path)
}

Remove_All :: proc(path: string) -> os.Error {
	return os.remove_all(path)
}

Rename :: proc(old_path, new_path: string) -> os.Error {
	return os.rename(old_path, new_path)
}

Write_File :: proc(path: string, data: []byte) -> os.Error {
	return os.write_entire_file(path, data)
}

Get_File_Name :: proc(path: string) -> string {
	return strings.trim_prefix(path[strings.last_index(path, "/") + 1:], "")
}

Get_Parent_Directory :: proc(path: string) -> string {
	if idx := strings.last_index(path, "/"); idx >= 0 {
		return path[:idx]
	}
	return ""
}


@(private)
mkdir_all_direct :: proc(path: string) -> os.Error {
	if path == "" {
		return .Invalid_Path
	}
	if os.exists(path) {
		return nil if os.is_directory(path) else .Exist
	}
	return mkdir_all_dir(path)

	mkdir_all_dir :: proc(path: string) -> os.Error {
		if idx := strings.last_index(path, "/"); idx > 0 {
			if err := mkdir_all_dir(path[:idx]); err != nil {
				return err
			}
		}
		err := os.make_directory(path)
		if err == .Exist {
			err = nil
		}
		return err
	}
}

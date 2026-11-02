package extensions


import "core:dynlib"
import "core:strings"


when ODIN_OS == .Windows {
	LIBRARY_SUFFIXES := [?]string{"dll"}
} else when ODIN_OS == .Darwin {
	LIBRARY_SUFFIXES := [?]string{"dylib", "so"}
} else {
	LIBRARY_SUFFIXES := [?]string{"so", "dylib"}
}


when ODIN_OS == .Windows {
	LIBRARY_FILENAME_SUFFIX :: ".dll"
} else when ODIN_OS == .Darwin {
	LIBRARY_FILENAME_SUFFIX :: ".dylib"
} else {
	LIBRARY_FILENAME_SUFFIX :: ".so"
}

Platform_Library :: struct {
	handle: dynlib.Library,
	path:   string,
}

platform_is_library_name :: proc(name: string) -> bool {
	for suffix in LIBRARY_SUFFIXES {
		if len(name) <= len(suffix) + 1 {
			continue
		}
		if name[len(name) - len(suffix) - 1] != '.' {
			continue
		}
		if strings.has_suffix(name, suffix) {
			return true
		}
	}
	return false
}




platform_join :: proc(directory, name: string) -> string {
	if len(directory) == 0 {
		return strings.clone(name)
	}
	last := directory[len(directory) - 1]
	if last == '/' || last == '\\' {
		return strings.concatenate({directory, name})
	}
	return strings.concatenate({directory, "/", name})
}


platform_load :: proc(path: string) -> (library: Platform_Library, err: string) {
	when ODIN_OS == .JS || ODIN_OS == .WASI {
		_ = path
		return {}, "native extensions are not supported on this platform"
	} else {
		handle, loaded := dynlib.load_library(path)
		if !loaded {
			reason := dynlib.last_error()
			return {}, strings.concatenate({"cannot load ", path, ": ", reason})
		}
		return Platform_Library{handle = handle, path = strings.clone(path)}, ""
	}
}

platform_unload :: proc(library: ^Platform_Library) -> string {
	if library == nil || library.handle == nil {
		return ""
	}
	when ODIN_OS == .JS || ODIN_OS == .WASI {
		library.handle = nil
		return ""
	} else {
		unloaded := dynlib.unload_library(library.handle)
		library.handle = nil
		if !unloaded {
			return dynlib.last_error()
		}
		return ""
	}
}

platform_symbol :: proc(library: Platform_Library, name: string) -> (rawptr, bool) {
	if library.handle == nil {
		return nil, false
	}
	when ODIN_OS == .JS || ODIN_OS == .WASI {
		_ = name
		return nil, false
	} else {
		return dynlib.symbol_address(library.handle, name)
	}
}

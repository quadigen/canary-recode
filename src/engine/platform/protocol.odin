#+build !js
package platform

import "core:fmt"

when ODIN_OS == .Windows {
	foreign import kernel32 "system:Kernel32.lib"

	HKEY :: distinct rawptr

	HKEY_CURRENT_USER :: cast(HKEY)uintptr(0x80000001)
	KEY_WRITE :: 0x20006

	REG_SZ :: 1

	foreign kernel32 {
		RegCreateKeyExW :: proc(
			hKey: HKEY,
			lpSubKey: [^]u16,
			Reserved: u32,
			lpClass: [^]u16,
			dwOptions: u32,
			samDesired: u32,
			lpSecurityAttributes: rawptr,
			phkResult: ^HKEY,
			lpdwDisposition: ^u32,
		) -> i32 ---

		RegSetValueExW :: proc(
			hKey: HKEY,
			lpValueName: [^]u16,
			Reserved: u32,
			dwType: u32,
			lpData: rawptr,
			cbData: u32,
		) -> i32 ---

		RegCloseKey :: proc(hKey: HKEY) -> i32 ---
	}
}

utf8_to_wstring :: proc(s: string) -> []u16 {
	n := len(s)
	result := make([]u16, n + 1)
	for i := 0; i < n; i += 1 {
		result[i] = u16(s[i])
	}
	result[n] = 0
	return result
}

when ODIN_OS == .Windows {
	register_protocol :: proc(exe_path: string) -> bool {
		subkeys := []string{
			"Software\\Classes\\kinemium",
			"Software\\Classes\\kinemium\\shell\\open\\command",
		}

		command := fmt.aprintf("\"%s\" \"%s\"", exe_path, "%1")
		defer delete(command)

		for key_path in subkeys {
			key: HKEY
			disposition: u32

			key_path_w := utf8_to_wstring(key_path)
			defer delete(key_path_w)

			result := RegCreateKeyExW(
				HKEY_CURRENT_USER,
				raw_data(key_path_w),
				0,
				nil,
				0,
				KEY_WRITE,
				nil,
				&key,
				&disposition,
			)

			if result != 0 {
				return false
			}

			defer RegCloseKey(key)

			if key_path == subkeys[0] {
				name := utf8_to_wstring("URL Protocol")
				defer delete(name)

				empty: u8 = 0

				RegSetValueExW(
					key,
					raw_data(name),
					0,
					REG_SZ,
					&empty,
					1,
				)

				description := utf8_to_wstring("URL:Kinemium Protocol")
				defer delete(description)

				RegSetValueExW(
					key,
					nil,
					0,
					REG_SZ,
					raw_data(description),
					u32(len(description) * size_of(u16)),
				)
			} else {
				value := utf8_to_wstring(command)
				defer delete(value)

				RegSetValueExW(
					key,
					nil,
					0,
					REG_SZ,
					raw_data(value),
					u32(len(value) * size_of(u16)),
				)
			}
		}

		return true
	}
} else {
	register_protocol :: proc(exe_path: string) -> bool {
		return false
	}
}

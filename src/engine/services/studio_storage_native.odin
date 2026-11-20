#+build !js
package services

import fsutil "../fsutil"
import "core:os"

studio_settings_path :: proc() -> (string, bool) {

	data_dir, err := os.user_data_dir(context.allocator)

	if err != nil {

		return "", false

	}

	defer delete(data_dir)

	kinemium_dir, join_err := os.join_path({data_dir, "Kinemium"}, context.allocator)

	if join_err != nil {

		return "", false

	}

	if !os.exists(kinemium_dir) {

		if make_err := fsutil.Make_Directory_All(kinemium_dir); make_err != nil {

			delete(kinemium_dir)

			return "", false

		}

	}

	path, path_err := os.join_path({kinemium_dir, "studio-settings.json"}, context.allocator)

	delete(kinemium_dir)

	if path_err != nil {

		return "", false

	}

	return path, true

}

studio_read_settings :: proc() -> ([]u8, bool) {
	path, ok := studio_settings_path()
	if !ok {return nil, false}
	defer delete(path)
	data, err := os.read_entire_file(path, context.allocator)
	return data, err == nil
}
studio_write_settings :: proc(data: []u8) {
	path, ok := studio_settings_path()
	if !ok {return}
	defer delete(path)
	_ = os.write_entire_file(path, data)
}

#+build !js
package serializer

import assetstore "../assetstore"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

read_project_script_asset :: proc(root, path: string) -> []u8 {
	if root == "" || filepath.is_abs(path) {return nil}
	resolved, err := filepath.join({root, path}, context.temp_allocator)
	if err != nil {return nil}
	data, _ := assetstore.Read_Asset_File(resolved)
	return data
}

bundle_project_files :: proc(w: ^Writer, root_path, output_path, output_directory_path: string) -> Error {
	root, root_err := filepath.abs(root_path, context.temp_allocator)
	output_file, output_ok := absolute_export_path(output_path)
	if root_err != nil || !output_ok {
		return Error_Make(.Invalid_Argument, -1, "could not resolve the project or export path")
	}
	output_directory := ""
	if output_directory_path != "" {
		output_directory, output_ok = absolute_export_path(output_directory_path)
		if !output_ok {
			return Error_Make(.Invalid_Argument, -1, "could not resolve the executable output directory")
		}
	}
	total: i64
	if !collect_project_files(w, root, "", output_file, output_directory, &total) {
		return writer_error(w, .Internal, "could not bundle the project files")
	}
	return Error_None
}

absolute_export_path :: proc(path: string) -> (string, bool) {
	if filepath.is_abs(path) {
		cleaned, err := filepath.clean(path, context.temp_allocator)
		return cleaned, err == nil
	}
	cwd, cwd_err := os.get_working_directory(context.temp_allocator)
	if cwd_err != nil {return "", false}
	joined, err := filepath.join({cwd, path}, context.temp_allocator)
	return joined, err == nil
}

// Collect regular project files before walking the tree so property and script
// references can share the same bytes. The URI is independent of the host path.
collect_project_files :: proc(
	w: ^Writer, root, relative, output_file, output_directory: string, total: ^i64,
) -> bool {
	directory, join_err := filepath.join({root, relative}, context.allocator)
	if join_err != nil {return writer_skip(w, "could not resolve project path %q", relative)}
	defer delete(directory)
	handle, open_err := os.open(directory)
	if open_err != nil {return writer_skip(w, "could not open project directory %q: %v", directory, open_err)}
	defer os.close(handle)
	entries, read_err := os.read_dir(handle, -1, context.allocator)
	if read_err != nil {return writer_skip(w, "could not list project directory %q: %v", directory, read_err)}
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		name := entry.name
		if name == ".git" || name == ".kinemium-backups" || name == ".kinemium-sync.json" ||
		   strings.has_prefix(name, ".project-save-") || strings.has_prefix(name, ".kinemium-write-") ||
		   (relative == "" && (name == "build" || name == "autosave.kine")) {
			continue
		}
		path := name if relative == "" else fmt.tprintf("%s/%s", relative, name)
		full_path, err := filepath.join({root, path}, context.allocator)
		if err != nil {return writer_skip(w, "could not resolve project file %q", path)}
		defer delete(full_path)
		if os.are_paths_identical(full_path, output_file) ||
		   os.are_paths_identical(full_path, output_directory) {continue}
		if entry.type == .Directory {
			if !collect_project_files(w, root, path, output_file, output_directory, total) {return false}
		} else if entry.type == .Regular {
			if entry.size > i64(assetstore.MAX_ASSET_BYTES) ||
			   total^ + entry.size > i64(assetstore.MAX_ASSET_TOTAL_BYTES) ||
			   len(w.used_ids) >= assetstore.MAX_ASSET_COUNT {
				return writer_skip(w, "project file %q exceeds the embedded asset limits", path)
			}
			data, ok := assetstore.Read_Asset_File(full_path)
			if !ok {return writer_skip(w, "could not read project file %q", path)}
			total^ += i64(len(data))
			uri := fmt.tprintf("%s%s", assetstore.PROJECT_ASSET_SCHEME, path)
			if !note_path_asset(w, uri, data) {return writer_skip(w, "could not embed project file %q", path)}
			w.project_files[strings.clone(uri)] = true
		}
	}
	return true
}

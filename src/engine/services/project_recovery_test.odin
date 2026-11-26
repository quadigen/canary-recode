#+build !js
package services

import "core:fmt"
import "core:os"
import "core:testing"

@(test)
project_backup_streaming_preserves_versions :: proc(t: ^testing.T) {
	temp, err := os.make_directory_temp(".", ".project-backup-test-*", context.allocator)
	testing.expect(t, err == nil, "test backup folder should be creatable")
	if err != nil {return}
	defer delete(temp)
	defer os.remove_all(temp)

	snapshot := fmt.tprintf("%s/autosave.kine", temp)
	pending := fmt.tprintf("%s/pending.kine", temp)
	testing.expect(
		t,
		os.write_entire_file_from_string(snapshot, "before") == nil,
		"write old version",
	)
	testing.expect(
		t,
		os.write_entire_file_from_string(pending, "before") == nil,
		"write matching version",
	)
	equal, ok := project_files_equal(snapshot, pending)
	testing.expect(t, ok && equal, "same bytes compare equal")
	backed, unchanged := project_backup_previous(temp, snapshot, pending)
	testing.expect(t, backed && unchanged, "unchanged snapshot must skip backup")
	testing.expect(
		t,
		len(project_backup_names(temp)) == 0,
		"unchanged snapshot must not create backup",
	)

	testing.expect(
		t,
		os.write_entire_file_from_string(pending, "after") == nil,
		"write updated version",
	)
	equal, ok = project_files_equal(snapshot, pending)
	testing.expect(t, ok && !equal, "different content must compare unequal")
	backed, unchanged = project_backup_previous(temp, snapshot, pending)
	testing.expect(t, backed && !unchanged, "changed snapshot must be backed up")
	backups := project_backup_names(temp)
	testing.expect(t, len(backups) == 1, "exactly one previous version is retained")
	if len(backups) > 0 {
		saved := fmt.tprintf("%s/%s", project_backup_directory(temp), backups[0])
		identical, compared := project_files_equal(snapshot, saved)
		testing.expect(t, compared && identical, "backup must reproduce previous snapshot exactly")
	}


	a := fmt.tprintf("%s/large-a.kine", temp)
	b := fmt.tprintf("%s/large-b.kine", temp)
	paths := [2]string{a, b}
	for path in paths {
		file, create_err := os.create(path)
		testing.expect(t, create_err == nil, "create sparse input")
		if create_err != nil {return}
		trunc_err := os.truncate(file, 16 * 1024 * 1024)
		testing.expect(t, trunc_err == nil, "grow sparse input")
		os.close(file)
		if trunc_err != nil {return}
	}
	identical, compared := project_files_equal(a, b)
	testing.expect(t, compared && identical, "matching 16 MiB files compare equal")
	testing.expect(t, os.write_entire_file_from_string(b, "short") == nil, "shrink second file")
	identical, compared = project_files_equal(a, b)
	testing.expect(t, compared && !identical, "size mismatch compares unequal")
}

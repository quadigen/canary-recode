#+build !js
package services

import tracy "../util/odin-tracy"
import vm "../vm"
import "core:bytes"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:thread"
import "core:time"

PROJECT_BACKUP_LIMIT :: 5
PROJECT_AUTOSAVE_SECONDS :: 60

Project_Autosave_Job :: struct {
	path: string,
	data: []u8,
}

project_autosave_worker :: proc(worker: ^thread.Thread) {
	when tracy.TRACY_ENABLE {
		context.allocator = tracy.DefaultContext().allocator
	}
	job := cast(^Project_Autosave_Job)worker.data
	if !project_write_snapshot(job.path, job.data) {
		fmt.eprintln("[Project] Automatic save failed")
	}
}

project_finish_autosave :: proc(service: ^ProjectService, wait: bool) -> bool {
	worker := service.autosave_worker
	if worker == nil {return true}
	if !wait && !thread.is_done(worker) {return false}
	thread.join(worker)
	job := cast(^Project_Autosave_Job)worker.data
	delete(job.path)
	delete(job.data)
	free(job)
	thread.destroy(worker)
	service.autosave_worker = nil
	return true
}

project_backup_name_valid :: proc(name: string) -> bool {
	if len(name) != 24 || !strings.has_suffix(name, ".kine") {return false}
	for digit in name[:19] {
		if digit < '0' || digit > '9' {return false}
	}
	return true
}

project_backup_directory :: proc(path: string) -> string {
	return fmt.tprintf("%s/.kinemium-backups", path)
}

project_backup_names :: proc(path: string) -> [dynamic]string {
	names := make([dynamic]string, context.temp_allocator)
	directory := project_backup_directory(path)
	info, info_err := os.lstat(directory, context.allocator)
	if info_err != nil {return names}
	defer os.file_info_delete(info, context.allocator)
	if info.type != .Directory {return names}
	dir, open_err := os.open(directory)
	if open_err != nil {return names}
	defer os.close(dir)
	entries, err := os.read_dir(dir, -1, context.allocator)
	if err != nil {return names}
	defer os.file_info_slice_delete(entries, context.allocator)
	for entry in entries {
		if entry.type == .Regular && project_backup_name_valid(entry.name) {
			append(&names, strings.clone(entry.name, context.temp_allocator))
		}
	}
	slice.sort_by(names[:], proc(a, b: string) -> bool {return a > b})
	return names
}

project_backup_previous :: proc(project_path, snapshot, pending: string) -> (ok, unchanged: bool) {
	if !os.exists(snapshot) {return true, false}
	previous, read_err := os.read_entire_file(snapshot, context.allocator)
	if read_err != nil {return false, false}
	defer delete(previous)
	next, next_err := os.read_entire_file(pending, context.allocator)
	if next_err != nil {return false, false}
	defer delete(next)
	if bytes.equal(previous, next) {return true, true}

	directory := project_backup_directory(project_path)
	if err := os.make_directory(directory); err != nil && err != .Exist {return false, false}
	info, info_err := os.lstat(directory, context.allocator)
	if info_err != nil {return false, false}
	defer os.file_info_delete(info, context.allocator)
	if info.type != .Directory {return false, false}

	name := fmt.tprintf("%019d.kine", time.to_unix_nanoseconds(time.now()))
	if !project_write_atomic(fmt.tprintf("%s/%s", directory, name), string(previous)) {
		return false, false
	}
	names := project_backup_names(project_path)
	for index := PROJECT_BACKUP_LIMIT; index < len(names); index += 1 {
		_ = os.remove(fmt.tprintf("%s/%s", directory, names[index]))
	}
	return true, false
}

project_push_backups :: proc(service: ^ProjectService, L: ^vm.State) {
	project := Project_Get_Active(service)
	if project == nil {
		vm.NewTable(L, 0, 0)
		return
	}
	names := project_backup_names(project.path)
	vm.NewTable(L, len(names), 0)
	for name, index in names {
		vm.NewTable(L, 0, 2)
		vm.PushString(L, name)
		vm.SetField(L, -2, "Id")
		info, err := os.stat(
			fmt.tprintf("%s/%s", project_backup_directory(project.path), name),
			context.allocator,
		)
		if err == nil {
			vm.PushInteger(L, time.to_unix_seconds(info.modification_time))
			vm.SetField(L, -2, "Timestamp")
			os.file_info_delete(info, context.allocator)
		}
		vm.SetArrayValue(L, -2, index + 1)
	}
}

project_restore_backup :: proc(service: ^ProjectService, L: ^vm.State, name: string) -> bool {
	project := Project_Get_Active(service)
	if project == nil || !project_backup_name_valid(name) {return false}
	names := project_backup_names(project.path)
	if !slice.contains(names[:], name) {return false}
	path := fmt.tprintf("%s/%s", project_backup_directory(project.path), name)
	info, stat_err := os.lstat(path, context.allocator)
	if stat_err != nil {return false}
	defer os.file_info_delete(info, context.allocator)
	if info.type != .Regular {return false}
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {return false}
	defer delete(data)

	// Protect the current in-memory project before replacing the scene.
	if !Project_Save_To_File(service, L) {return false}
	if !Restore_Map(
		service.data_model.registry,
		L,
		data,
		path,
		clear_assets = false,
	) {return false}
	return Project_Save_To_File(service, L)
}

Project_Autosave :: proc(registry: ^Registry, L: ^vm.State, dt: f32 = 0, closing := false) {
	if registry == nil || L == nil || registry.mode != .Editor {return}
	descriptor := Find_Service(registry, "Project")
	if descriptor == nil || descriptor.object == nil {return}
	service := cast(^ProjectService)descriptor.object
	ready := project_finish_autosave(service, closing)
	project := Project_Get_Active(service)
	if project == nil {return}
	service.autosave_elapsed += max(dt, 0)
	if !closing && (!ready || service.autosave_elapsed < PROJECT_AUTOSAVE_SECONDS) {return}
	service.autosave_elapsed = 0
	previous := vm.GetThreadSecurityCapabilities(L)
	vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
	defer vm.SetThreadSecurityCapabilities(L, previous)
	if closing {
		if !Project_Save_To_File(service, L) {fmt.eprintln("[Project] Automatic save failed")}
		return
	}
	data, ok := project_snapshot(service, L)
	if !ok {return}
	if worker := thread.create(project_autosave_worker); worker != nil {
		job := new(Project_Autosave_Job)
		job^ = {
			path = strings.clone(project.path),
			data = data,
		}
		worker.data = job
		service.autosave_worker = worker
		thread.start(worker)
		return
	}
	defer delete(data)
	if !project_write_snapshot(
		project.path,
		data,
	) {fmt.eprintln("[Project] Automatic save failed")}
}

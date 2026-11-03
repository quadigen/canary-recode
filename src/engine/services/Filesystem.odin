#+build !js

package services

// wire:service global="Filesystem"

import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import fsutil "../fsutil"
import vm "../vm"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Filesystem_Class := classes.Class_Info {
	name   = "Filesystem",
	parent = &Service_Class,
}

Filesystem :: struct {
	using service: Service,
	call_count:    i64,
}

Filesystem_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Filesystem)
	service.service = Service_Init(&Filesystem_Class, "Filesystem", data_model)
	return &service.object
}

Filesystem_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	service := cast(^Filesystem)object
	switch key {
	case "PathExists",
	     "IsDirectory",
	     "CreateFile",
	     "CreateFolder",
	     "DeletePath",
	     "RenamePath",
	     "MovePath",
	     "CopyPath",
	     "ReadFile",
	     "WriteFile", "WriteFileAtomic", "DeleteFile":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return false
		}

		vm.PushUserdataMethod(L, key)
	}
	return true
}

Filesystem_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (
	i32,
	bool,
) {
	service := cast(^Filesystem)object
	switch method {
	case "PathExists":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:PathExists() requires Internals capability"), true
		}

		path := vm.ArgString(L, 2)

		vm.PushBoolean(L, fsutil.Exists(path))
		return 1, true
	case "IsDirectory":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:IsDirectory() requires Internals capability"), true
		}

		path := vm.ArgString(L, 2)

		vm.PushBoolean(L, fsutil.Is_Directory(path))
		return 1, true
	case "CreateFile":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:CreateFile() requires Internals capability"), true
		}

		parent := vm.ArgString(L, 2)
		name := vm.ArgString(L, 3)

		if !Project_Name_Is_Valid(name) {
			vm.PushString(L, "")
			return 1, true
		}

		path, ok := Project_Join_Path(parent, name)
		if !ok {
			vm.PushString(L, "")
			return 1, true
		}
		defer delete(path)

		if os.exists(path) || fsutil.Write_File(path, []byte{}) != nil {
			vm.PushString(L, "")
			return 1, true
		}

		vm.PushString(L, path)
		return 1, true
	case "CreateFolder":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:CreateFolder() requires Internals capability"),
				true
		}

		parent := vm.ArgString(L, 2)
		name := vm.ArgString(L, 3)

		if !Project_Name_Is_Valid(name) {
			vm.PushString(L, "")
			return 1, true
		}

		path, ok := Project_Join_Path(parent, name)
		if !ok {
			vm.PushString(L, "")
			return 1, true
		}
		defer delete(path)

		if os.exists(path) || fsutil.Make_Directory_All(path) != nil {
			vm.PushString(L, "")
			return 1, true
		}

		vm.PushString(L, path)
		return 1, true
	case "DeletePath":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:DeletePath() requires Internals capability"), true
		}

		path := vm.ArgString(L, 2)

		if !os.exists(path) {
			vm.PushBoolean(L, false)
			return 1, true
		}

		if os.is_directory(path) {
			vm.PushBoolean(L, fsutil.Remove_All(path) == nil)
		} else {
			vm.PushBoolean(L, fsutil.Remove(path) == nil)
		}

		return 1, true
	case "RenamePath":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:RenamePath() requires Internals capability"), true
		}

		path := vm.ArgString(L, 2)
		new_name := vm.ArgString(L, 3)

		if !fsutil.Exists(path) || !Project_Name_Is_Valid(new_name) {
			vm.PushBoolean(L, false)
			return 1, true
		}

		parent, ok := Project_Entry_Parent(path)
		if !ok {
			vm.PushBoolean(L, false)
			return 1, true
		}

		destination, join_ok := Project_Join_Path(parent, new_name)
		if !join_ok {
			vm.PushBoolean(L, false)
			return 1, true
		}
		defer delete(destination)

		if os.exists(destination) && !Project_Is_Case_Only_Rename(path, destination) {
			vm.PushBoolean(L, false)
			return 1, true
		}

		vm.PushBoolean(L, fsutil.Rename(path, destination) == nil)
		return 1, true
	case "MovePath":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:MovePath() requires Internals capability"), true
		}

		path := vm.ArgString(L, 2)
		new_parent := vm.ArgString(L, 3)

		if !fsutil.Exists(path) || !fsutil.Is_Directory(new_parent) {
			vm.PushBoolean(L, false)
			return 1, true
		}

		if Project_Is_Same_Or_Descendant(new_parent, path) {
			vm.PushBoolean(L, false)
			return 1, true
		}

		destination, ok := Project_Join_Path(new_parent, Project_Entry_Name(path))
		if !ok {
			vm.PushBoolean(L, false)
			return 1, true
		}
		defer delete(destination)

		if os.exists(destination) && !Project_Is_Case_Only_Rename(path, destination) {
			vm.PushBoolean(L, false)
			return 1, true
		}

		vm.PushBoolean(L, fsutil.Rename(path, destination) == nil)
		return 1, true
	case "CopyPath":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:CopyPath() requires Internals capability"), true
		}

		path := vm.ArgString(L, 2)
		new_parent := vm.ArgString(L, 3)

		if !fsutil.Exists(path) || !fsutil.Is_Directory(new_parent) {
			vm.PushString(L, "")
			return 1, true
		}

		if Project_Is_Same_Or_Descendant(new_parent, path) {
			vm.PushString(L, "")
			return 1, true
		}

		destination, ok := Project_Unique_Child_Path(new_parent, Project_Entry_Name(path))
		if !ok {
			vm.PushString(L, "")
			return 1, true
		}
		defer delete(destination)

		if !Project_Copy_Entry(path, destination) {
			vm.PushString(L, "")
			return 1, true
		}

		vm.PushString(L, destination)
		return 1, true
	case "ReadFile":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:ReadFile() requires Internals capability"), true
		}

		path := vm.ArgString(L, 2)

		if !fsutil.Is_File(path) {
			vm.PushNil(L)
			return 1, true
		}

		data, err := os.read_entire_file(path, context.allocator)
		if err != nil {
			vm.PushNil(L)
			return 1, true
		}
		defer delete(data, context.allocator)

		vm.PushBytes(L, data)
		return 1, true
	case "WriteFileAtomic", "DeleteFile":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem mutation requires Internals capability"), true
		}
		path := vm.ArgString(L, 2)
		ok: bool
		if method == "DeleteFile" {
			info, err := os.lstat(path, context.allocator)
			if err == nil {
				defer os.file_info_delete(info, context.allocator)
				ok = info.type == .Regular && os.remove(path) == nil
			}
		} else {
			ok = project_write_atomic(path, vm.ArgString(L, 3))
		}
		vm.PushBoolean(L, ok)
		return 1, true
	case "WriteFile":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {
			return vm.RaiseError(L, "Filesystem:WriteFile() requires Internals capability"), true
		}

		path := vm.ArgString(L, 2)
		content := vm.ArgString(L, 3)

		vm.PushBoolean(L, fsutil.Write_File(path, transmute([]byte)content) == nil)
		return 1, true
	}
	return 0, false
}

Filesystem_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Filesystem)object)
}

Register_Filesystem_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Filesystem_Class,
		Filesystem_construct,
		Filesystem_destroy,
		creatable = false,
		get = Filesystem_get,
		namecall = Filesystem_namecall,
	)
}

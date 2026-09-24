package packages
import "core:fmt"
import "core:strings"
import base_runtime "base:runtime"
import sdl3 "../platform"
import renderer "../renderer"
import vm "../vm"
import kineffi "../bindings"
import target "../target"

Package_Installer    :: proc(L: ^vm.State, ctx: rawptr, renderer_object: ^renderer.RendererObject)
Package_Begin_Frame  :: proc(ctx: rawptr, width, height: i32)
Package_Descriptor :: struct {
    name:        string,
    installer:   Package_Installer,
    begin_frame: Package_Begin_Frame,
    ctx:         rawptr,
    reference:   i32,
}
Pool_Phase :: enum {
    TwoD,
    TwoDAbove,
    ThreeD,
    Gizmo,
}
Draw_Callback :: struct {
    id:        f64,
    reference: i32,
    priority:  i32,
    phase:     Pool_Phase,
}
Hook_Kind :: enum {
    Before3D,
    After3D,
    Before2D,
    After2D,
    Renderstep,
    Afterstep,
    Shutdown,
}
Hook_Callback :: struct {
    reference: i32,
    kind:      Hook_Kind,
}
Pending_Click :: struct {
    button: u8,
    x:      f32,
    y:      f32,
    down:   bool,
}
Font_Entry :: struct {
    name: string,
    path: string,
    size: f64,
}
Internal_Module :: struct {
    name: string,
    source: string,
    reference: i32,
    owned: bool,
}
Registry :: struct {
    vm_state: ^vm.VM,
    renderer: ^renderer.RendererObject,
    packages:  [dynamic]Package_Descriptor,
    callbacks: [dynamic]Draw_Callback,
    hooks:     [dynamic]Hook_Callback,
    contexts:  Package_Contexts,
    width:  i32,
    height: i32,
    next_callback_id: f64,
    mouse_x:       f32,
    mouse_y:       f32,
    mouse_delta_x: f32,
    mouse_delta_y: f32,
    mouse_wheel:   f32,
    pending_clicks: [dynamic]Pending_Click,
    fonts:             [dynamic]Font_Entry,
    font_resolver_ref:   i32,
    runtime_library_ref: i32,
    active_camera_ref: i32,
    profiler_ref:      i32,
    internal_modules: [dynamic]Internal_Module,
    dimension_3d: bool,
    running:      bool,
}
// -----------------------------------------------------------------------------
// Generic helpers
// -----------------------------------------------------------------------------
abs_index :: proc(L: ^vm.State, index: int) -> int {
    if index >= 0 {
        return index
    }
    return vm.StackTop(L) + index + 1
}
table_number :: proc(
    L: ^vm.State,
    index: int,
    name: string,
    default: f32 = 0,
) -> f32 {
    idx := abs_index(L, index)
    value_type := vm.GetField(L, idx, name)
    defer vm.Pop(L)
    if value_type != .Number && value_type != .Integer {
        return default
    }
    return f32(vm.ArgNumber(L, -1))
}
table_string :: proc(
    L: ^vm.State,
    index: int,
    name: string,
    default: string = "",
) -> string {
    idx := abs_index(L, index)
    value_type := vm.GetField(L, idx, name)
    defer vm.Pop(L)
    if value_type != .String {
        return default
    }
    return vm.ArgString(L, -1)
}
function_offset :: proc(L: ^vm.State) -> int {
    // renderer:Foo(...) / renderer.Pool:new(...)
    // versus renderer.Foo(...) / renderer.Pool.new(...)
    return vm.IsTable(L, 1) ? 1 : 0
}
registry_from_upvalue :: proc(L: ^vm.State) -> ^Registry {
    return cast(^Registry)vm.UpvaluePointer(L)
}
set_registry_function :: proc(
    L: ^vm.State,
    name: string,
    function: vm.CFunction,
    registry: ^Registry,
) {
    vm.PushLightUserdata(L, registry)
    vm.PushFunction(L, name, function, 1)
    vm.SetField(L, -2, name)
}
point_in_rect :: proc(
    x, y: f32,
    rect_x, rect_y, rect_width, rect_height: f32,
) -> bool {
    return x >= rect_x &&
           x <= rect_x + rect_width &&
           y >= rect_y &&
           y <= rect_y + rect_height
}
invoke_callback :: proc(
    registry: ^Registry,
    reference: i32,
) {
    if registry == nil ||
       registry.vm_state == nil ||
       registry.vm_state.L == nil ||
       reference <= 0 {
        return
    }
    L := registry.vm_state.L

    // Render-loop callbacks are first-party internal scripts that need full
    // access to engine services (e.g. StudioThemeService.SelectedTheme).
    // Temporarily grant THREAD_SECURITY_ALL, same as RunInternal, and restore
    // the previous capabilities when done.
    previous_caps := vm.GetThreadSecurityCapabilities(L)
    vm.SetThreadSecurityCapabilities(L, vm.THREAD_SECURITY_ALL)
    defer vm.SetThreadSecurityCapabilities(L, previous_caps)

    vm.PushRegistryReference(L, reference)
    if registry.runtime_library_ref > 0 {
        vm.PushRegistryReference(
            L,
            registry.runtime_library_ref,
        )
    } else {
        vm.NewTable(L, 0, 0)
    }
    ok, err := vm.ProtectedCall(L, 1, 0)
    if !ok {
        fmt.eprintf(
            "renderer compatibility callback failed: %s\n",
            err,
        )
        delete(err)
    }
}
invoke_hook_kind :: proc(
    registry: ^Registry,
    kind: Hook_Kind,
) {
    for hook in registry.hooks {
        if hook.kind == kind {
            invoke_callback(registry, hook.reference)
        }
    }
}
invoke_pool_phase :: proc(
    registry: ^Registry,
    phase: Pool_Phase,
) {
    for callback in registry.callbacks {
        if callback.phase == phase {
            invoke_callback(registry, callback.reference)
        }
    }
}
phase_from_string :: proc(
    value: string,
) -> (Pool_Phase, bool) {
    switch value {
    case "2d":
        return .TwoD, true
    case "2da":
        return .TwoDAbove, true
    case "3d":
        return .ThreeD, true
    case "gizmo", "gizmos":
        return .Gizmo, true
    }
    return .TwoD, false
}
hook_from_string :: proc(
    value: string,
) -> (Hook_Kind, bool) {
    switch value {
    case "Before3D":
        return .Before3D, true
    case "After3D":
        return .After3D, true
    case "Before2D":
        return .Before2D, true
    case "After2D":
        return .After2D, true
    case "Renderstep":
        return .Renderstep, true
    case "Afterstep":
        return .Afterstep, true
    case "Shutdown":
        return .Shutdown, true
    }
    return .Before2D, false
}
// -----------------------------------------------------------------------------
// Package registration / require()
// -----------------------------------------------------------------------------
Register_Package :: proc(
    registry: ^Registry,
    name: string,
    installer: Package_Installer,
    begin_frame: Package_Begin_Frame,
    ctx: rawptr,
) {
    assert(registry != nil)
    assert(installer != nil)
    for descriptor in registry.packages {
        assert(descriptor.name != name)
    }
    append(
        &registry.packages,
        Package_Descriptor{
            name        = name,
            installer   = installer,
            begin_frame = begin_frame,
            ctx         = ctx,
        },
    )
}
Resolve :: proc(
    L: ^vm.State,
    path: string,
    raw_registry: rawptr,
) -> bool {
    registry := cast(^Registry)raw_registry
    if registry == nil {
        return false
    }
    internal_name := path
    if strings.has_prefix(internal_name, "@internal/") {
        internal_name = internal_name[len("@internal/"):]
    } else if strings.has_prefix(internal_name, "internal/") {
        internal_name = internal_name[len("internal/"):]
    } else {
        internal_name = ""
    }
    if internal_name != "" &&
       !strings.contains(internal_name, "..") &&
       !strings.contains(internal_name, "\\") &&
       !strings.has_prefix(internal_name, "/") {
        if strings.has_suffix(internal_name, ".luau") {
            internal_name = internal_name[:len(internal_name)-len(".luau")]
        }
        for &module in registry.internal_modules {
            if module.name == internal_name {
                if module.reference <= 0 {
                    ok, err := vm.LoadSource(
                        registry.vm_state,
                        L,
                        module.source,
                        strings.concatenate({"internal/", module.name}),
                    )
                    if !ok {
                        return vm.RaiseError(L, err) > 0
                    }
                    ok, err = vm.ProtectedCall(L, 0, 1)
                    if !ok {
                        return vm.RaiseError(L, err) > 0
                    }
                    module.reference = vm.RetainValue(L)
                    vm.Pop(L)
                }
                vm.PushRegistryReference(L, module.reference)
                return true
            }
        }
    }
    name := path
    if strings.has_prefix(path, "@engine/") {
        name = path[len("@engine/"):]
    } else if len(path) > 1 && path[0] == '@' {
        name = path[1:]
    } else {
        return false
    }
    for descriptor in registry.packages {
        if descriptor.name == name &&
           descriptor.reference > 0 {
            vm.PushRegistryReference(
                L,
                descriptor.reference,
            )
            return true
        }
    }
    return false
}

destroy_internal_modules :: proc(
    modules: ^[dynamic]Internal_Module,
    L: ^vm.State = nil,
) {
    for &module in modules {
        if L != nil && module.reference > 0 {
            vm.ReleaseValue(L, module.reference)
        }
        if module.owned {
            delete(module.name)
            delete(module.source)
        }
    }
    delete(modules^)
    modules^ = nil
}

Load_Internal_Modules_From_Blob :: proc(
    registry: ^Registry,
    archive_path: string,
) -> bool {
    when ODIN_OS == .JS {
        fmt.eprintln("[EditorModules] archive loading is unavailable on Web")
        return false
    } else {
    if registry == nil {
        fmt.eprintln("[EditorModules] package registry is nil")
        return false
    }

    archive, opened := kineffi.Zip_Open(archive_path)
    if !opened {
        fmt.eprintf("[EditorModules] failed opening archive: %s\n", archive_path)
        return false
    }
    defer kineffi.Zip_Close(archive)

    loaded := make([dynamic]Internal_Module)
    keep_loaded := false
    defer if !keep_loaded {
        destroy_internal_modules(&loaded)
    }

    found_entrypoint := false
    for index := u32(0); index < kineffi.Zip_File_Count(archive); index += 1 {
        archive_name, named := kineffi.Zip_File_Name(archive, index)
        if !named {
            continue
        }

        module_path := ""
        if strings.has_prefix(archive_name, "internal/") {
            module_path = archive_name[len("internal/"):]
        } else if marker := strings.index(archive_name, "/internal/"); marker >= 0 {
            module_path = archive_name[marker + len("/internal/"):]
        }

        if module_path == "" ||
           !strings.has_suffix(module_path, ".luau") ||
           strings.contains(module_path, "..") ||
           strings.contains(module_path, "\\") {
            delete(archive_name)
            continue
        }

        data, read := kineffi.Zip_Read_Index(archive, index)
        if !read {
            fmt.eprintf("[EditorModules] failed reading archive entry %d: %s\n", index, archive_name)
            delete(archive_name)
            return false
        }

        module_name := module_path[:len(module_path)-len(".luau")]
        append(&loaded, Internal_Module{
            name = strings.clone(module_name),
            source = strings.clone(string(data)),
            owned = true,
        })
        found_entrypoint = found_entrypoint || module_name == "editor_ui"

        delete(data)
        delete(archive_name)
    }

    if !found_entrypoint {
        fmt.eprintf("[EditorModules] archive has no editor_ui module: %s\n", archive_path)
        return false
    }

    L: ^vm.State
    if registry.vm_state != nil {
        L = registry.vm_state.L
    }
    destroy_internal_modules(&registry.internal_modules, L)
    registry.internal_modules = loaded
    keep_loaded = true
    fmt.eprintf("[EditorModules] loaded %d modules from %s\n", len(loaded), archive_path)
    return true
    }
}
// -----------------------------------------------------------------------------
// renderer.Pool
// -----------------------------------------------------------------------------
pool_new :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        return vm.RaiseError(L, "renderer registry is unavailable")
    }
    offset := function_offset(L)
    phase_name := vm.ArgString(L, 1+offset)
    phase, valid_phase := phase_from_string(phase_name)
    if !valid_phase {
        return vm.RaiseError(
            L,
            "renderer.Pool.new phase must be '2d', '2da', '3d', or 'gizmo'",
        )
    }
    callback_index := 2+offset
    if !vm.IsFunction(L, callback_index) {
        return vm.RaiseError(
            L,
            "renderer.Pool.new expects a callback",
        )
    }
    priority := i32(
        vm.ArgOptionalNumber(
            L,
            3+offset,
            0,
        ),
    )
    reference := vm.RetainValue(L, callback_index)
    registry.next_callback_id += 1
    entry := Draw_Callback{
        id        = registry.next_callback_id,
        reference = reference,
        priority  = priority,
        phase     = phase,
    }
    append(&registry.callbacks, entry)
    // Stable insertion sort by priority inside the complete callback list.
    for index := len(registry.callbacks)-1;
        index > 0 &&
        registry.callbacks[index-1].priority > priority;
        index -= 1 {
        registry.callbacks[index] =
            registry.callbacks[index-1]
        registry.callbacks[index-1] = entry
    }
    vm.PushNumber(L, entry.id)
    return 1
}
pool_remove :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        return 0
    }
    offset := function_offset(L)
    id := vm.ArgNumber(L, 1+offset)
    for callback, index in registry.callbacks {
        if callback.id == id {
            if callback.reference > 0 &&
               registry.vm_state != nil &&
               registry.vm_state.L != nil {
                vm.ReleaseValue(
                    registry.vm_state.L,
                    callback.reference,
                )
            }
            ordered_remove(
                &registry.callbacks,
                index,
            )
            vm.PushBoolean(L, true)
            return 1
        }
    }
    vm.PushBoolean(L, false)
    return 1
}
// -----------------------------------------------------------------------------
// renderer.Hook
// -----------------------------------------------------------------------------
hook_new :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        return vm.RaiseError(L, "renderer registry is unavailable")
    }
    offset := function_offset(L)
    name := vm.ArgString(L, 1+offset)
    kind, ok := hook_from_string(name)
    if !ok {
        return vm.RaiseError(
            L,
            "unknown renderer hook",
        )
    }
    callback_index := 2+offset
    if !vm.IsFunction(L, callback_index) {
        return vm.RaiseError(
            L,
            "renderer.Hook.new expects a callback",
        )
    }
    reference := vm.RetainValue(
        L,
        callback_index,
    )
    append(
        &registry.hooks,
        Hook_Callback{
            reference = reference,
            kind      = kind,
        },
    )
    vm.PushNumber(L, f64(reference))
    return 1
}
// -----------------------------------------------------------------------------
// Input compatibility
// -----------------------------------------------------------------------------
renderer_set_3d_tex_props :: proc "c" (L: ^vm.State) -> i32 {
	context = base_runtime.default_context()

	registry := registry_from_upvalue(L)
	if registry == nil ||
	   registry.renderer == nil {
		return 0
	}

	offset := function_offset(L)

	x      := i32(vm.ArgNumber(L, 1+offset))
	y      := i32(vm.ArgNumber(L, 2+offset))
	width  := i32(vm.ArgNumber(L, 3+offset))
	height := i32(vm.ArgNumber(L, 4+offset))

	if width <= 0 || height <= 0 {
		registry.renderer.RenderFilament = false
	} else {
        if !registry.renderer.RenderFilament {
            registry.renderer.RenderFilament = true
        }
    }

	renderer.set_viewport_rect(
		registry.renderer,
		x,
		y,
		width,
		height,
	)
	renderer.apply_viewport_rect(registry.renderer)

	if vm.IsTable(L, 1) {
		vm.NewTable(L, 0, 4)

		vm.PushNumber(L, f64(x))
		vm.SetField(L, -2, "x")

		vm.PushNumber(L, f64(y))
		vm.SetField(L, -2, "y")

		vm.PushNumber(L, f64(width))
		vm.SetField(L, -2, "width")

		vm.PushNumber(L, f64(height))
		vm.SetField(L, -2, "height")

		vm.SetField(L, 1, "tex3d_rect")
	}

	return 0
}

renderer_has_clicked :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        vm.PushBoolean(L, false)
        return 1
    }
    offset := function_offset(L)
    rect_index := 1+offset
    if !vm.IsTable(L, rect_index) {
        vm.PushBoolean(L, false)
        return 1
    }
    x := table_number(L, rect_index, "x")
    y := table_number(L, rect_index, "y")
    width := table_number(L, rect_index, "width")
    height := table_number(L, rect_index, "height")
    for click in registry.pending_clicks {
        if click.button == 1 &&
           !click.down &&
           point_in_rect(
                click.x,
                click.y,
                x, y,
                width, height,
           ) {
            vm.PushBoolean(L, true)
            return 1
        }
    }
    vm.PushBoolean(L, false)
    return 1
}
renderer_mouse_in_rect :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    offset := function_offset(L)
    rect_index := 1+offset
    if registry == nil ||
       !vm.IsTable(L, rect_index) {
        vm.PushBoolean(L, false)
        return 1
    }
    x := table_number(L, rect_index, "x")
    y := table_number(L, rect_index, "y")
    width := table_number(L, rect_index, "width")
    height := table_number(L, rect_index, "height")
    mouse_x, mouse_y: f32
    _ = sdl3.GetMouseState(
        &mouse_x,
        &mouse_y,
    )
    registry.mouse_x = mouse_x
    registry.mouse_y = mouse_y
    vm.PushBoolean(
        L,
        point_in_rect(
            mouse_x,
            mouse_y,
            x, y,
            width, height,
        ),
    )
    return 1
}
renderer_get_mouse_position :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    x, y: f32
    _ = sdl3.GetMouseState(&x, &y)
    if registry != nil {
        registry.mouse_x = x
        registry.mouse_y = y
    }
    vm.NewTable(L, 0, 2)
    vm.PushNumber(L, f64(x))
    vm.SetField(L, -2, "X")
    vm.PushNumber(L, f64(y))
    vm.SetField(L, -2, "Y")
    return 1
}
renderer_watch_key :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    // Canary needed this because its renderer manually polled only watched keys.
    // SDL3 exposes the complete keyboard state, so no registration is required.
    return 0
}
renderer_stop_watching_key :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    return 0
}
// -----------------------------------------------------------------------------
// Basic renderer methods
// -----------------------------------------------------------------------------
renderer_set_dimension :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    offset := function_offset(L)
    dimension := vm.ArgString(L, 1+offset)
    if dimension != "2D" &&
       dimension != "3D" {
        vm.PushBoolean(L, false)
        return 1
    }
    if registry != nil {
        registry.dimension_3d = dimension == "3D"
    }
    if vm.IsTable(L, 1) {
        vm.PushString(L, dimension)
        vm.SetField(L, 1, "Dimension")
    }
    vm.PushBoolean(L, true)
    return 1
}
renderer_get_active_camera :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil ||
       registry.active_camera_ref <= 0 {
        vm.PushNil(L)
        return 1
    }
    vm.PushRegistryReference(
        L,
        registry.active_camera_ref,
    )
    return 1
}
renderer_use_camera :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        return 0
    }
    offset := function_offset(L)
    camera_index := 1+offset
    if registry.active_camera_ref > 0 {
        vm.ReleaseValue(
            L,
            registry.active_camera_ref,
        )
        registry.active_camera_ref = -1
    }
    if !vm.IsNoneOrNil(L, camera_index) {
        registry.active_camera_ref =
            vm.RetainValue(
                L,
                camera_index,
            )
    }
    return 0
}
renderer_set_profiler :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        return 0
    }
    offset := function_offset(L)
    value_index := 1+offset
    if registry.profiler_ref > 0 {
        vm.ReleaseValue(
            L,
            registry.profiler_ref,
        )
        registry.profiler_ref = -1
    }
    if !vm.IsNoneOrNil(L, value_index) {
        registry.profiler_ref =
            vm.RetainValue(
                L,
                value_index,
            )
    }
    for module in registry.internal_modules {
        if module.reference > 0 {
            vm.ReleaseValue(registry.vm_state.L, module.reference)
        }
    }
    return 0
}
renderer_get_view_matrix :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    // The native renderer currently exposes WorldToView internally as 12 floats
    // but does not yet expose the old Canary Matrix API.
    vm.PushNil(L)
    return 1
}
renderer_resize :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    offset := function_offset(L)
    if registry != nil {
        width := i32(vm.ArgNumber(L, 1+offset))
        height := i32(vm.ArgNumber(L, 2+offset))
        if width > 0 && height > 0 {
            registry.width = width
            registry.height = height
        }
    }
    // The Vulkan renderer itself owns resize handling from SDL window events.
    return 0
}
renderer_sync_window_size :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    return 0
}
renderer_stop :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry != nil {
        registry.running = false
    }
    // Native renderer.init() currently owns its run loop, so this compatibility
    // flag does not force-close the SDL window yet.
    return 0
}
renderer_noop :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    return 0
}
renderer_return_nil :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    vm.PushNil(L)
    return 1
}
renderer_return_false :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    vm.PushBoolean(L, false)
    return 1
}
renderer_return_zero :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    vm.PushNumber(L, 0)
    return 1
}
// -----------------------------------------------------------------------------
// renderer.Font
// -----------------------------------------------------------------------------
find_font_index :: proc(
    registry: ^Registry,
    name: string,
) -> int {
    if registry == nil {
        return -1
    }
    for font, index in registry.fonts {
        if font.name == name {
            return index
        }
    }
    return -1
}
push_font_table :: proc(
    L: ^vm.State,
    font: ^Font_Entry,
) {
    if font == nil {
        vm.PushNil(L)
        return
    }
    vm.NewTable(L, 0, 3)
    vm.PushString(L, font.name)
    vm.SetField(L, -2, "name")
    vm.PushString(L, font.path)
    vm.SetField(L, -2, "path")
    vm.PushNumber(L, font.size)
    vm.SetField(L, -2, "size")
}
font_new :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        vm.PushNil(L)
        return 1
    }
    offset := function_offset(L)
    name := vm.ArgString(L, 1+offset)
    path := vm.ArgString(L, 2+offset)
    size := vm.ArgOptionalNumber(
        L,
        3+offset,
        24,
    )
    index := find_font_index(
        registry,
        name,
    )
    if index < 0 {
        append(
            &registry.fonts,
            Font_Entry{
                name = strings.clone(name),
                path = strings.clone(path),
                size = size,
            },
        )
        index = len(registry.fonts)-1
    }
    push_font_table(
        L,
        &registry.fonts[index],
    )
    return 1
}
font_get :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        vm.PushNil(L)
        return 1
    }
    offset := function_offset(L)
    name := vm.ArgString(L, 1+offset)
    index := find_font_index(
        registry,
        name,
    )
    if index >= 0 {
        push_font_table(
            L,
            &registry.fonts[index],
        )
        return 1
    }
    if registry.font_resolver_ref > 0 {
        vm.PushRegistryReference(
            L,
            registry.font_resolver_ref,
        )
        vm.PushString(L, name)
        ok, err := vm.ProtectedCall(
            L,
            1,
            1,
        )
        if !ok {
            fmt.eprintf(
                "renderer.Font resolver failed: %s\n",
                err,
            )
            delete(err)
            vm.PushNil(L)
        }
        return 1
    }
    vm.PushNil(L)
    return 1
}
font_remove :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        return 0
    }
    offset := function_offset(L)
    name := vm.ArgString(L, 1+offset)
    index := find_font_index(
        registry,
        name,
    )
    if index >= 0 {
        delete(registry.fonts[index].name)
        delete(registry.fonts[index].path)
        ordered_remove(
            &registry.fonts,
            index,
        )
    }
    return 0
}
font_set_resolver :: proc "c" (L: ^vm.State) -> i32 {
    context = base_runtime.default_context()
    registry := registry_from_upvalue(L)
    if registry == nil {
        return 0
    }
    offset := function_offset(L)
    resolver_index := 1+offset
    if registry.font_resolver_ref > 0 {
        vm.ReleaseValue(
            L,
            registry.font_resolver_ref,
        )
        registry.font_resolver_ref = -1
    }
    if vm.IsFunction(L, resolver_index) {
        registry.font_resolver_ref =
            vm.RetainValue(
                L,
                resolver_index,
            )
    }
    return 0
}
// -----------------------------------------------------------------------------
// Legacy compatibility tables
// -----------------------------------------------------------------------------
install_noop_function :: proc(
    L: ^vm.State,
    name: string,
    registry: ^Registry,
) {
    set_registry_function(
        L,
        name,
        renderer_noop,
        registry,
    )
}
install_legacy_mesh :: proc(
    L: ^vm.State,
    registry: ^Registry,
) {
    vm.NewTable(L, 0, 8)
    for name in ([?]string{
        "LoadMesh",
        "UnloadMesh",
        "GetMesh",
        "GenerateMesh",
        "PreloadStandardMeshes",
        "GetModelRegistry",
        "drawModel",
        "loadMaterialOnModel",
    }) {
        if name == "GetMesh" {
            set_registry_function(
                L,
                name,
                renderer_return_nil,
                registry,
            )
        } else {
            install_noop_function(
                L,
                name,
                registry,
            )
        }
    }
}
install_legacy_shader :: proc(
    L: ^vm.State,
    registry: ^Registry,
) {
    vm.NewTable(L, 0, 10)
    for name in ([?]string{
        "LoadShader",
        "LoadShaderCode",
        "GetShaderUniformLocation",
        "SetShaderUniform",
        "SetShaderValueRaw",
        "SetShaderTextureRaw",
        "SetShaderTexture",
        "UnloadShader",
    }) {
        if name == "GetShaderUniformLocation" {
            set_registry_function(
                L,
                name,
                renderer_return_zero,
                registry,
            )
        } else {
            install_noop_function(
                L,
                name,
                registry,
            )
        }
    }
}
install_legacy_freecam :: proc(
    L: ^vm.State,
    registry: ^Registry,
) {
    vm.NewTable(L, 0, 6)
    for name in ([?]string{
        "Update",
        "SetSpeed",
        "SetSensitivity",
        "SetCFrame",
    }) {
        install_noop_function(
            L,
            name,
            registry,
        )
    }
    set_registry_function(
        L,
        "GetCFrame",
        renderer_return_nil,
        registry,
    )
    set_registry_function(
        L,
        "GetPos",
        renderer_return_nil,
        registry,
    )
}
install_legacy_texture :: proc(
    L: ^vm.State,
    registry: ^Registry,
) {
    vm.NewTable(L, 0, 4)
    set_registry_function(
        L,
        "LoadTextureFromFile",
        renderer_return_nil,
        registry,
    )
    set_registry_function(
        L,
        "LoadTextureFromFileAsync",
        renderer_return_nil,
        registry,
    )
    vm.NewTable(L, 0, 0)
    vm.SetField(L, -2, "Materials")
}
install_legacy_blur :: proc(
    L: ^vm.State,
    registry: ^Registry,
) {
    vm.NewTable(L, 0, 10)
    for name in ([?]string{
        "SetBlurRadius",
        "BeginCapture",
        "EndCapture",
        "ApplyBlur",
        "DrawFullBlur",
        "DrawMixed",
        "DrawBlurredRegion",
        "DrawUnblurred",
        "Enable",
        "Disable",
        "Cleanup",
    }) {
        install_noop_function(
            L,
            name,
            registry,
        )
    }
    vm.PushBoolean(L, true)
    vm.SetField(L, -2, "enabled")
}
install_legacy_mesh_pool :: proc(
    L: ^vm.State,
    registry: ^Registry,
) {
    vm.NewTable(L, 0, 12)
    for name in ([?]string{
        "DrawMesh",
        "DrawMeshList",
        "CreateInstanceBatch",
        "UpdateInstanceTransforms",
        "DestroyInstanceBatch",
        "DrawMeshInstanced",
        "CreateMaterial",
        "AddMesh",
        "RemoveMesh",
    }) {
        install_noop_function(
            L,
            name,
            registry,
        )
    }
}
// -----------------------------------------------------------------------------
// renderer table installation
// -----------------------------------------------------------------------------
install_renderer_global :: proc(
    registry: ^Registry,
) {
    L := registry.vm_state.L
    vm.NewTable(L, 0, 48)
    renderer_index := abs_index(L, -1)
    vm.PushNumber(L, 0)
    vm.SetField(L, renderer_index, "Width")
    vm.PushNumber(L, 0)
    vm.SetField(L, renderer_index, "Height")
    vm.PushString(L, "3D")
    vm.SetField(L, renderer_index, "Dimension")
    vm.PushLightUserdata(
        L,
        registry.renderer,
    )
    vm.SetField(L, renderer_index, "Window")
    vm.PushBoolean(L, true)
    vm.SetField(L, renderer_index, "UpdateCamera")
    vm.PushBoolean(L, true)
    vm.SetField(L, renderer_index, "Enable3D")
    vm.PushBoolean(L, false)
    vm.SetField(L, renderer_index, "Enable3DRT")
    vm.PushBoolean(L, true)
    vm.SetField(L, renderer_index, "DrawFps")
    vm.PushBoolean(L, false)
    vm.SetField(L, renderer_index, "ShowPerfOverlay")
    vm.PushNil(L)
    vm.SetField(L, renderer_index, "TDRT")
    vm.PushNil(L)
    vm.SetField(L, renderer_index, "tex3d_rect")
    // RuntimeLibrary
    vm.NewTable(L, 0, 6)
    vm.PushNumber(L, 0)
    vm.SetField(L, -2, "dt")
    vm.PushNumber(L, 0)
    vm.SetField(L, -2, "time")
    vm.NewTable(L, 0, 16)
    vm.SetField(L, -2, "perf")
    registry.runtime_library_ref =
        vm.RetainValue(L)
    vm.SetField(L, renderer_index, "RuntimeLibrary")
    // PerfStats is a compatibility mirror. update_renderer_global keeps the
    // common values synchronized.
    vm.NewTable(L, 0, 16)
    vm.SetField(L, renderer_index, "PerfStats")
    // Pool
    vm.NewTable(L, 0, 2)
    set_registry_function(
        L,
        "new",
        pool_new,
        registry,
    )
    set_registry_function(
        L,
        "remove",
        pool_remove,
        registry,
    )
    vm.SetField(L, renderer_index, "Pool")
    // Hook
    vm.NewTable(L, 0, 1)
    set_registry_function(
        L,
        "new",
        hook_new,
        registry,
    )
    vm.SetField(L, renderer_index, "Hook")
    // Font
    vm.NewTable(L, 0, 5)
    set_registry_function(
        L,
        "new",
        font_new,
        registry,
    )
    set_registry_function(
        L,
        "Get",
        font_get,
        registry,
    )
    set_registry_function(
        L,
        "getFontTexture",
        font_get,
        registry,
    )
    set_registry_function(
        L,
        "Remove",
        font_remove,
        registry,
    )
    set_registry_function(
        L,
        "SetResolver",
        font_set_resolver,
        registry,
    )
    vm.SetField(L, renderer_index, "Font")
    // Compatibility methods.
    set_registry_function(
        L,
        "HasClicked",
        renderer_has_clicked,
        registry,
    )
    set_registry_function(
        L,
        "isMouseInRect",
        renderer_mouse_in_rect,
        registry,
    )
    set_registry_function(
        L,
        "GetMousePosition",
        renderer_get_mouse_position,
        registry,
    )
    set_registry_function(
        L,
        "SetDimension",
        renderer_set_dimension,
        registry,
    )
    set_registry_function(
        L,
        "WatchKey",
        renderer_watch_key,
        registry,
    )
    set_registry_function(
        L,
        "StopWatchingKey",
        renderer_stop_watching_key,
        registry,
    )
    set_registry_function(
        L,
        "UseRlCamera",
        renderer_use_camera,
        registry,
    )
    set_registry_function(
        L,
        "GetActiveCamera",
        renderer_get_active_camera,
        registry,
    )
    set_registry_function(
        L,
        "SetProfiler",
        renderer_set_profiler,
        registry,
    )
    set_registry_function(
        L,
        "GetViewMatrix",
        renderer_get_view_matrix,
        registry,
    )
    set_registry_function(
        L,
        "GetProjectionMatrix",
        renderer_get_view_matrix,
        registry,
    )
    set_registry_function(
        L,
        "GetInverseProjectionMatrix",
        renderer_get_view_matrix,
        registry,
    )
    set_registry_function(
        L,
        "Resize",
        renderer_resize,
        registry,
    )
    set_registry_function(
        L,
        "SyncWindowSize",
        renderer_sync_window_size,
        registry,
    )
    set_registry_function(
        L,
        "Stop",
        renderer_stop,
        registry,
    )
    set_registry_function(
        L,
        "Set3DTexProps",
        renderer_set_3d_tex_props,
        registry,
    )

    for name in ([?]string{
        "MakeDepthBuffer",
        "SetGlobalShader",
        "SetIcon",
        "SetResizable",
        "Include",
        "InitAudioDevice",
        "Render3D",
        "Render2D",
        "Render2DAbove",
        "Step",
        "Run",
    }) {
        install_noop_function(
            L,
            name,
            registry,
        )
    }

    install_legacy_mesh(L, registry)
    vm.SetField(L, renderer_index, "Mesh")
    install_legacy_shader(L, registry)
    vm.SetField(L, renderer_index, "Shader")
    install_legacy_freecam(L, registry)
    vm.SetField(L, renderer_index, "Freecam")
    install_legacy_texture(L, registry)
    vm.SetField(L, renderer_index, "Texture")
    install_legacy_blur(L, registry)
    vm.SetField(L, renderer_index, "Blur")
    install_legacy_mesh_pool(L, registry)
    vm.SetField(L, renderer_index, "MeshPool")
    vm.NewTable(L, 0, 0)
    vm.SetField(L, renderer_index, "Skybox")
    vm.NewTable(L, 0, 0)
    vm.SetField(L, renderer_index, "Raylib")
    vm.NewTable(L, 0, 0)
    vm.SetField(L, renderer_index, "Draw")
    vm.SetGlobalFromStack(
        registry.vm_state,
        "renderer",
    )
}

Init :: proc(
    registry: ^Registry,
    vm_state: ^vm.VM,
    renderer_object: ^renderer.RendererObject,
) {
    assert(registry != nil)
    registry.vm_state = vm_state
    registry.renderer = renderer_object
    registry.font_resolver_ref = -1
    registry.runtime_library_ref = -1
    registry.active_camera_ref = -1
    registry.profiler_ref = -1
    registry.dimension_3d = true
    registry.running = true
    Register_Default_Packages(registry)
    for &descriptor in registry.packages {
        descriptor.installer(
            vm_state.L,
            descriptor.ctx,
            renderer_object,
        )
        assert(vm.IsTable(vm_state.L, -1))
        descriptor.reference =
            vm.RetainValue(vm_state.L)
        vm.PushValue(vm_state.L, -1)
        vm.SetGlobalFromStack(
            vm_state,
            descriptor.name,
        )
        vm.Pop(vm_state.L)
    }
    install_renderer_global(registry)
    vm.AddGlobal_Boolean(
        vm_state,
        "IsServer",
        target.is_server(),
    )
    vm.AddGlobal_Boolean(
        vm_state,
        "IsClient",
        target.is_client(),
    )
    vm.AddGlobal_Boolean(vm_state, "IsEditor", target.is_editor())
    vm.AddGlobal_String(vm_state, "BuildTarget", target.name())
    vm.NewTable(vm_state.L, 0, 8)
    vm.SetGlobalFromStack(
        vm_state,
        "ishared",
    )
}
update_renderer_global :: proc(
    registry: ^Registry,
    delta_time: f32,
    advance_time := false,
) {
    L := registry.vm_state.L
    if vm.GetGlobal(L, "renderer") != .Table {
        vm.Pop(L)
        return
    }
    defer vm.Pop(L)
    vm.PushNumber(
        L,
        f64(registry.width),
    )
    vm.SetField(L, -2, "Width")
    vm.PushNumber(
        L,
        f64(registry.height),
    )
    vm.SetField(L, -2, "Height")
    if vm.GetField(L, -1, "RuntimeLibrary") == .Table {
        vm.PushNumber(L, f64(delta_time))
        vm.SetField(L, -2, "dt")
        if advance_time {
            if vm.GetField(L, -1, "time") == .Number {
                current_time := vm.ArgNumber(L, -1)
                vm.Pop(L)
                vm.PushNumber(
                    L,
                    current_time + f64(delta_time),
                )
                vm.SetField(L, -2, "time")
            } else {
                vm.Pop(L)
            }
        }
    }
    vm.Pop(L)
    if vm.GetField(L, -1, "PerfStats") == .Table {
        vm.PushNumber(
            L,
            f64(delta_time)*1000,
        )
        vm.SetField(L, -2, "frame_ms")
        fps: f64 = 0
        if delta_time > 0 {
            fps = 1.0/f64(delta_time)
        }
        vm.PushNumber(L, fps)
        vm.SetField(L, -2, "fps")
    }
    vm.Pop(L)
}
Set_Event :: proc(
    registry: ^Registry,
    event: sdl3.Event,
) {
    if registry == nil {
        return
    }
    #partial switch event.type {
    case .MOUSE_MOTION:
        registry.mouse_x = event.motion.x
        registry.mouse_y = event.motion.y
        registry.mouse_delta_x += event.motion.xrel
        registry.mouse_delta_y += event.motion.yrel
    case .MOUSE_BUTTON_DOWN:
        registry.mouse_x = event.button.x
        registry.mouse_y = event.button.y
        append(
            &registry.pending_clicks,
            Pending_Click{
                button = u8(event.button.button),
                x      = event.button.x,
                y      = event.button.y,
                down   = true,
            },
        )
    case .MOUSE_BUTTON_UP:
        registry.mouse_x = event.button.x
        registry.mouse_y = event.button.y
        append(
            &registry.pending_clicks,
            Pending_Click{
                button = u8(event.button.button),
                x      = event.button.x,
                y      = event.button.y,
                down   = false,
            },
        )
    case .MOUSE_WHEEL:
        registry.mouse_wheel += event.wheel.y
    }
}
Update :: proc(
    registry: ^Registry,
    delta_time: f32,
) {
    if registry == nil ||
       registry.vm_state == nil ||
       registry.vm_state.L == nil {
        return
    }
    update_renderer_global(
        registry,
        delta_time,
        true,
    )
    invoke_hook_kind(
        registry,
        .Renderstep,
    )
    invoke_hook_kind(
        registry,
        .Afterstep,
    )
}
Render_3D :: proc(
    registry: ^Registry,
    delta_time: f32,
) {
    if registry == nil ||
       registry.vm_state == nil ||
       registry.vm_state.L == nil {
        return
    }
    update_renderer_global(
        registry,
        delta_time,
    )
    invoke_hook_kind(
        registry,
        .Before3D,
    )
    invoke_pool_phase(
        registry,
        .ThreeD,
    )
}
Render_3D_Above :: proc(
    registry: ^Registry,
    delta_time: f32,
) {
    if registry == nil ||
       registry.vm_state == nil ||
       registry.vm_state.L == nil {
        return
    }
    update_renderer_global(
        registry,
        delta_time,
    )
    // Gizmos are intentionally after the native scene.
    invoke_pool_phase(
        registry,
        .Gizmo,
    )
    invoke_hook_kind(
        registry,
        .After3D,
    )
}
Render_2D :: proc(
    registry: ^Registry,
    width, height: i32,
    delta_time: f32,
) {
    if registry == nil ||
       registry.vm_state == nil ||
       registry.vm_state.L == nil {
        return
    }
    registry.width = width
    registry.height = height
    mouse_x, mouse_y: f32
    _ = sdl3.GetMouseState(
        &mouse_x,
        &mouse_y,
    )
    registry.mouse_x = mouse_x
    registry.mouse_y = mouse_y
    for descriptor in registry.packages {
        if descriptor.begin_frame != nil {
            descriptor.begin_frame(
                descriptor.ctx,
                width,
                height,
            )
        }
    }
    update_renderer_global(
        registry,
        delta_time,
    )
    invoke_hook_kind(
        registry,
        .Before2D,
    )
    invoke_pool_phase(
        registry,
        .TwoD,
    )
}
Render_2D_Above :: proc(
    registry: ^Registry,
    width, height: i32,
    delta_time: f32,
) {
    if registry == nil ||
       registry.vm_state == nil ||
       registry.vm_state.L == nil {
        return
    }
    registry.width = width
    registry.height = height
    update_renderer_global(
        registry,
        delta_time,
    )
    // "2da" means GUI above the native retained UI pass.
    invoke_pool_phase(
        registry,
        .TwoDAbove,
    )
    invoke_hook_kind(
        registry,
        .After2D,
    )
    // Canary pending clicks were frame-scoped.
    resize(
        &registry.pending_clicks,
        0,
    )
    registry.mouse_wheel = 0
    registry.mouse_delta_x = 0
    registry.mouse_delta_y = 0
}
// -----------------------------------------------------------------------------
// Shutdown
// -----------------------------------------------------------------------------
Destroy :: proc(
    registry: ^Registry,
) {
    if registry == nil {
        return
    }
    if registry.vm_state != nil &&
       registry.vm_state.L != nil {
        invoke_hook_kind(
            registry,
            .Shutdown,
        )
        for callback in registry.callbacks {
            if callback.reference > 0 {
                vm.ReleaseValue(
                    registry.vm_state.L,
                    callback.reference,
                )
            }
        }
        for hook in registry.hooks {
            if hook.reference > 0 {
                vm.ReleaseValue(
                    registry.vm_state.L,
                    hook.reference,
                )
            }
        }
        for descriptor in registry.packages {
            if descriptor.reference > 0 {
                vm.ReleaseValue(
                    registry.vm_state.L,
                    descriptor.reference,
                )
            }
        }
        if registry.font_resolver_ref > 0 {
            vm.ReleaseValue(
                registry.vm_state.L,
                registry.font_resolver_ref,
            )
        }
        if registry.runtime_library_ref > 0 {
            vm.ReleaseValue(
                registry.vm_state.L,
                registry.runtime_library_ref,
            )
        }
        if registry.active_camera_ref > 0 {
            vm.ReleaseValue(
                registry.vm_state.L,
                registry.active_camera_ref,
            )
        }
        if registry.profiler_ref > 0 {
            vm.ReleaseValue(
                registry.vm_state.L,
                registry.profiler_ref,
            )
        }
    }
    for &font in registry.fonts {
        delete(font.name)
        delete(font.path)
    }
    delete(registry.fonts)
    delete(registry.pending_clicks)
    delete(registry.hooks)
    delete(registry.callbacks)
    delete(registry.packages)
    destroy_internal_modules(&registry.internal_modules)
    registry^ = Registry{}
}

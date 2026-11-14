package services
// wire:service
import "core:bytes"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "vendor:sdl3"

import platform "../platform"
import classes "../classes"
import datatypes "../datatypes"
import enums "../enum"
import vm "../vm"

logo_bytes := #load("../assets/images/KinemiumWhite.png")

when ODIN_OS == .Linux {
	desktop_entry_marker :: "X-Kinemium-Generated=true"
	desktop_entry_file :: "kinemium.desktop"
	desktop_icon_file :: "kinemium.png"

	install_desktop_integration :: proc() {
		data_home := os.get_env("XDG_DATA_HOME", context.temp_allocator)
		if data_home == "" {
			home := os.get_env("HOME", context.temp_allocator)
			if home == "" {
				fmt.eprintln("[Window] desktop entry: neither XDG_DATA_HOME nor HOME is set")
				return
			}
			data_home, _ = filepath.join({home, ".local", "share"}, context.temp_allocator)
		}

		executable, executable_err := os.get_executable_path(context.temp_allocator)
		if executable_err != nil {
			fmt.eprintln("[Window] desktop entry: cannot resolve the executable: ", executable_err)
			return
		}

		applications_dir, _ := filepath.join({data_home, "applications"}, context.temp_allocator)
		desktop_path, _ := filepath.join(
			{applications_dir, desktop_entry_file},
			context.temp_allocator,
		)

		escaped_executable, _ := strings.replace_all(executable, "%", "%%", context.temp_allocator)
		entry, _ := strings.concatenate(
			{
				"[Desktop Entry]\n",
				"Type=Application\n",
				"Name=Kinemium\n",
				"Comment=Kinemium game engine editor\n",
				"Exec=\"",
				escaped_executable,
				"\"\n",
				"Icon=kinemium\n",
				"Terminal=false\n",
				"Categories=Development;\n",
				"StartupNotify=true\n",
				"StartupWMClass=kinemium\n",
				desktop_entry_marker,
				"\n",
			},
			context.temp_allocator,
		)

		if existing, read_err := os.read_entire_file(desktop_path, context.temp_allocator);
		   read_err == nil {
			if !strings.contains(string(existing), desktop_entry_marker) {
				fmt.eprintln("[Window] desktop entry: keeping the existing ", desktop_path)
				install_desktop_icon(data_home)
				return
			}
			if string(existing) == entry {
				install_desktop_icon(data_home)
				return
			}
		}

		if err := os.make_directory_all(applications_dir);
		   err != nil && !os.is_directory(applications_dir) {
			fmt.eprintln("[Window] desktop entry: cannot create ", applications_dir, ": ", err)
			return
		}

		if err := os.write_entire_file_from_string(desktop_path, entry); err != nil {
			fmt.eprintln("[Window] desktop entry: cannot write ", desktop_path, ": ", err)
			return
		}

		install_desktop_icon(data_home)
	}

	install_desktop_icon :: proc(data_home: string) {
		hicolor_dir, _ := filepath.join(
			{data_home, "icons", "hicolor", "512x512", "apps"},
			context.temp_allocator,
		)
		hicolor_path, _ := filepath.join({hicolor_dir, desktop_icon_file}, context.temp_allocator)
		write_desktop_icon(hicolor_dir, hicolor_path)

		pixmaps_dir, _ := filepath.join({data_home, "pixmaps"}, context.temp_allocator)
		pixmaps_path, _ := filepath.join({pixmaps_dir, desktop_icon_file}, context.temp_allocator)
		write_desktop_icon(pixmaps_dir, pixmaps_path)
	}

	write_desktop_icon :: proc(dir, path: string) {
		if existing, read_err := os.read_entire_file(path, context.temp_allocator);
		   read_err == nil {
			if bytes.equal(existing, logo_bytes[:]) {
				return
			}
		}
		if err := os.make_directory_all(dir); err != nil && !os.is_directory(dir) {
			fmt.eprintln("[Window] desktop icon: cannot create ", dir, ": ", err)
			return
		}
		if err := os.write_entire_file(path, logo_bytes[:]); err != nil {
			fmt.eprintln("[Window] desktop icon: cannot write ", path, ": ", err)
		}
	}
}

Window_Class := classes.Class_Info {
	name   = "Window",
	parent = &Service_Class,
}

Window :: struct {
	using service: Service,
}

// The service is stepped every frame, so remember whether the icon was already
// handed to SDL: decoding the PNG again would only waste CPU.
icon_applied := false

Window_construct :: proc(
	renderer: ^classes.Renderer_Object,
	data_model: rawptr,
) -> ^classes.Object {
	service := new(Window)
	service.service = Service_Init(&Window_Class, "Window", data_model)

	return &service.object
}

Window_step :: proc(object: ^classes.Object, ctx: ^classes.Class_Step_Context) {
	if icon_applied || ctx.renderer == nil || ctx.renderer.Window == nil {
		return
	}

	icon_applied = true

	when ODIN_OS == .Linux {
		install_desktop_integration()
	}

	io := sdl3.IOFromConstMem(raw_data(logo_bytes), len(logo_bytes))
	if io == nil {
		fmt.eprintln("[Window] could not open the embedded logo: ", sdl3.GetError())
		return
	}

	surface := sdl3.LoadPNG_IO(io, true)
	if surface == nil {
		fmt.eprintln("[Window] could not decode the embedded logo: ", sdl3.GetError())
		return
	}
	defer sdl3.DestroySurface(surface)

	if !sdl3.SetWindowIcon(ctx.renderer.Window, surface) {
		fmt.eprintln("[Window] could not set the window icon: ", sdl3.GetError())
	}
}

Window_get :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	key: string,
) -> bool {
	switch key {
	case "GetResolution", "SetResolution", "SetUIScale":
		if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {return false}
		vm.PushUserdataMethod(L, key)
		return true
	}
	return false
}

Window_namecall :: proc(
	L: ^vm.State,
	object: ^classes.Object,
	datatype_registry: ^datatypes.Registry,
	enum_registry: ^enums.Registry,
	method: string,
) -> (i32, bool) {
	service := cast(^Window)object
	if method != "GetResolution" && method != "SetResolution" && method != "SetUIScale" {return 0, false}

	if !vm.ThreadHasSecurityCapability(L, PROJECT_INTERNALS_CAPABILITY) {return 0, false}
	registry := service.data_model.registry
	if registry == nil || registry.mode != .Editor || registry.classes.renderer == nil {
		vm.PushBoolean(L, false)
		return 1, true
	}
	window := registry.classes.renderer.Window
	if window == nil {
		vm.PushNil(L)
		return 1, true
	}

	ok := false
	switch method {
	case "GetResolution":
		width, height: i32
		if !sdl3.GetWindowSize(window, &width, &height) {
			vm.PushNil(L)
		} else {
			datatypes.Push_Vector2(L, datatype_registry, {f32(width), f32(height)})
		}
		return 1, true
	case "SetResolution":
		width, height := vm.ArgNumber(L, 2), vm.ArgNumber(L, 3)
		if width >= 320 && width <= 7680 && height >= 240 && height <= 4320 {
			if .MAXIMIZED in sdl3.GetWindowFlags(window) {
				_ = sdl3.RestoreWindow(window)
			}
			ok = sdl3.SetWindowSize(window, i32(width), i32(height))
		}
	case "SetUIScale":
		scale := vm.ArgNumber(L, 2)
		if scale >= 0.75 && scale <= 2 {
			platform.UI_Scale = f32(scale)
			classes.Gui_Layout_Mark_Dirty()
			ok = true
		}
	}
	vm.PushBoolean(L, ok)
	return 1, true
}

Window_destroy :: proc(object: ^classes.Object, renderer: ^classes.Renderer_Object) {
	classes.Object_Destroy(object)
	free(cast(^Window)object)
}

Register_Window_Class :: proc(registry: ^classes.Registry) {
	classes.Register_Class(
		registry,
		&Window_Class,
		Window_construct,
		Window_destroy,
		creatable = false,
		_step = Window_step,
		get = Window_get,
		namecall = Window_namecall,
		methods = []string{"GetResolution", "SetResolution", "SetUIScale"},
	)
}

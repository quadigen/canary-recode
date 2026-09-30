package kineffi

when ODIN_OS == .JS {
    foreign import lib "../../../build/web-native/lib/kine_jolt_web.o"
} else when ODIN_OS == .Windows {
    foreign import lib {
        "../../../vendor/build/vendor/webview/core/webview.lib",
    }
} else when #config(KINE_ANDROID, false) {
    foreign import lib "../../../build/android-native/lib/libJoltWrapper.a"
} else {
    foreign import lib "../../../vendor/build/lib/KinemiumLibs.a"
}

import "core:c"

VERSION_MAJOR  :: 0
VERSION_MINOR  :: 12
VERSION_PATCH  :: 0
VERSION_NUMBER :: "0.12.0"

Webview :: distinct rawptr

Hint :: enum c.int {
    None,
    Min,
    Max,
    Fixed,
}

Native_Handle_Kind :: enum c.int {
    UI_Window,
    UI_Widget,
    Browser_Controller,
}

Error :: enum c.int {
    Missing_Dependency = -5,
    Canceled           = -4,
    Invalid_State      = -3,
    Invalid_Argument   = -2,
    Unspecified        = -1,
    Ok                 = 0,
    Duplicate          = 1,
    Not_Found          = 2,
}

Version :: struct {
    major: c.uint,
    minor: c.uint,
    patch: c.uint,
}

Version_Info :: struct {
    version:        Version,
    version_number: [32]c.char,
    pre_release:    [48]c.char,
    build_metadata: [48]c.char,
}

#assert(size_of(Version) == 12)
#assert(size_of(Version_Info) == 12 + 32 + 48 + 48)

Dispatch_Proc :: #type proc "c" (w: Webview, arg: rawptr)
Bind_Proc     :: #type proc "c" (seq: cstring, req: cstring, arg: rawptr)

@(default_calling_convention="c")
foreign lib {
    @(link_name="webview_create")
    create_raw :: proc(debug: c.int, window: rawptr) -> Webview ---

    @(link_name="webview_destroy")
    destroy :: proc(w: Webview) -> Error ---

    @(link_name="webview_run")
    run :: proc(w: Webview) -> Error ---

    @(link_name="webview_terminate")
    terminate :: proc(w: Webview) -> Error ---

    @(link_name="webview_dispatch")
    dispatch :: proc(w: Webview, fn: Dispatch_Proc, arg: rawptr) -> Error ---

    @(link_name="webview_get_window")
    get_window :: proc(w: Webview) -> rawptr ---

    @(link_name="webview_get_native_handle")
    get_native_handle :: proc(w: Webview, kind: Native_Handle_Kind) -> rawptr ---

    @(link_name="webview_set_title")
    set_title :: proc(w: Webview, title: cstring) -> Error ---

    @(link_name="webview_set_size")
    set_size :: proc(w: Webview, width, height: c.int, hints: Hint) -> Error ---

    @(link_name="webview_navigate")
    navigate :: proc(w: Webview, url: cstring) -> Error ---

    @(link_name="webview_set_html")
    set_html :: proc(w: Webview, html: cstring) -> Error ---

    @(link_name="webview_init")
    init :: proc(w: Webview, js: cstring) -> Error ---

    @(link_name="webview_eval")
    eval :: proc(w: Webview, js: cstring) -> Error ---

    @(link_name="webview_bind")
    bind :: proc(w: Webview, name: cstring, fn: Bind_Proc, arg: rawptr) -> Error ---

    @(link_name="webview_unbind")
    unbind :: proc(w: Webview, name: cstring) -> Error ---

    @(link_name="webview_return")
    ret :: proc(w: Webview, seq: cstring, status: c.int, result: cstring) -> Error ---

    @(link_name="webview_version")
    version :: proc() -> ^Version_Info ---
}

create :: proc "contextless" (debug: bool, window: rawptr = nil) -> Webview {
    return create_raw(c.int(debug), window)
}
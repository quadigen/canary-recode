#+build linux

package kineffi

import "core:c"

// A desktop Webview window cannot be created on Android. Keep the platform
// boundary explicit so WebviewService reports failure without unresolved
// desktop C API symbols in libmain.so.
when #config(KINE_ANDROID, false) {
    create_raw :: proc "c" (debug: c.int, window: rawptr) -> Webview { return nil }
    destroy :: proc "c" (w: Webview) -> Error { return .Missing_Dependency }
    run :: proc "c" (w: Webview) -> Error { return .Missing_Dependency }
    terminate :: proc "c" (w: Webview) -> Error { return .Missing_Dependency }
    dispatch :: proc "c" (w: Webview, fn: Dispatch_Proc, arg: rawptr) -> Error { return .Missing_Dependency }
    get_window :: proc "c" (w: Webview) -> rawptr { return nil }
    get_native_handle :: proc "c" (w: Webview, kind: Native_Handle_Kind) -> rawptr { return nil }
    set_title :: proc "c" (w: Webview, title: cstring) -> Error { return .Missing_Dependency }
    set_size :: proc "c" (w: Webview, width, height: c.int, hints: Hint) -> Error { return .Missing_Dependency }
    navigate :: proc "c" (w: Webview, url: cstring) -> Error { return .Missing_Dependency }
    set_html :: proc "c" (w: Webview, html: cstring) -> Error { return .Missing_Dependency }
    init :: proc "c" (w: Webview, js: cstring) -> Error { return .Missing_Dependency }
    eval :: proc "c" (w: Webview, js: cstring) -> Error { return .Missing_Dependency }
    bind :: proc "c" (w: Webview, name: cstring, fn: Bind_Proc, arg: rawptr) -> Error { return .Missing_Dependency }
    unbind :: proc "c" (w: Webview, name: cstring) -> Error { return .Missing_Dependency }
    ret :: proc "c" (w: Webview, seq: cstring, status: c.int, result: cstring) -> Error { return .Missing_Dependency }
    version :: proc "c" () -> ^Version_Info { return nil }
}

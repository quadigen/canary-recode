package main

import "core:fmt"
import "core:os"
import "core:time"

import engine_runtime "../src/engine/runtime"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("WebviewService smoke test failed")
	}
}

main :: proc() {
	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	open_lua := `
local w = game:GetService("WebviewService")
assert(w ~= nil)
assert(w.ClassName == "WebviewService")
assert(typeof(w.CallCount) == "number")
assert(typeof(w.Open) == "function")
assert(typeof(w.Close) == "function")
assert(typeof(w.Destroy) == "function")
assert(typeof(w.Navigate) == "function")
assert(typeof(w.SetTitle) == "function")
assert(typeof(w.SetHtml) == "function")
assert(typeof(w.Eval) == "function")

WV = w
ID1 = w:Open("https:
assert(typeof(ID1) == "number" and ID1 > 0, "Open should return a numeric id")
ID2 = w:Open("https:
assert(ID2 > ID1, "ids should increase")
`

	command_lua := `
-- Post-open commands are dispatched onto each window's UI thread. A true
-- return means the command was accepted and queued.
assert(WV:Navigate(ID1, "https:
assert(WV:SetTitle(ID1, "Updated Title") == true)
assert(WV:SetHtml(ID1, "<html><body>Hi</body></html>") == true)
assert(WV:Eval(ID1, "1+2") == true)

-- Unknown ids are rejected without dispatching.
assert(WV:Navigate(999999, "https:
assert(WV:SetTitle(999999, "nope") == false)
`

	close_lua := `
assert(WV:Close(ID1) == 1)
assert(WV:Close(ID1) == 0)
assert(WV:Destroy(ID2) == 1)
assert(WV:Destroy(ID2) == 0)

local a = WV:Open("https:
local b = WV:Open("https:
assert(a > 0 and b > 0)
-- Close() with no argument closes every remaining window.
local closed = WV:Close()
assert(closed >= 2, "Close() should close all windows")
`

	run_script(&script_vm, open_lua, "webview_open")
	time.sleep(300 * time.Millisecond)
	run_script(&script_vm, command_lua, "webview_commands")
	time.sleep(300 * time.Millisecond)
	run_script(&script_vm, close_lua, "webview_close")
	time.sleep(300 * time.Millisecond)

	vm.Close(&script_vm)
	engine_runtime.Environment_Destroy(&environment)

	fmt.println("WEBVIEW_SERVICE_SMOKE_PASSED")
	os.exit(0)
}

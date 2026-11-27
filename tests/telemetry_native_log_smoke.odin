package main

import services "../src/engine/services"
import "core:fmt"

check_log :: proc(input, expected: string) {
	actual := services.Telemetry_Sanitize_Native_Line(input, context.allocator)
	defer if actual != "" {delete(actual)}
	assert(actual == expected, fmt.tprintf("sanitize mismatch: input=%q actual=%q expected=%q", input, actual, expected))
}

main :: proc() {
	check_log("[Kine] Vulkan device lost during presentation", "[Kine] Vulkan device lost during presentation")
	check_log("[EditorService] failed opening /home/devcell/myproject.kine", "[EditorService] failed opening [redacted]")
	check_log("[Engine] cannot connect to https://example.com/private", "[Engine] cannot connect to [redacted]")
	check_log("[Renderer] GPU model: NVIDIA GeForce RTX 3050", "")
	check_log("[Startup] CPU model AMD Ryzen 7 7840HS", "")
	check_log("[Kine] driver version: 620.70.06", "")
	check_log("[HTTP] Authorization Bearer 1234567", "")
	check_log("[ScriptContext] script traceback abc", "")
	check_log("[Kine] renderer frame failed at vkQueuePresentKHR", "[Kine] renderer frame failed at vkQueuePresentKHR")
	services.Telemetry_LogCapture_Install()
	fmt.println("NATIVE_TELEMETRY_STDOUT_SMOKE")
	services.Telemetry_LogService_Output("INFO", "LUAU_LOGSERVICE_EXCLUDED")
	services.Telemetry_LogCapture_Uninstall()
	fmt.println("TELEMETRY_NATIVE_LOG_SMOKE_PASSED")
}

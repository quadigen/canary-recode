package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import services "../src/engine/services"

main :: proc() {
	path := "/tmp/kinemium-telemetry-journal-smoke.log"
	_ = os.remove(path)
	_ = os.remove("/tmp/kinemium-telemetry-journal-smoke.log.pending")
	first := services.Telemetry_Journal_Start_At(path)
	assert(first == "")
	services.Telemetry_Journal_Append("[EditorService] editor loading", "")
	services.Telemetry_Journal_Append("[Renderer] shader compiled", "")
	services.Telemetry_Journal_Stop(false)
	assert(os.is_file(path))
	previous := services.Telemetry_Journal_Start_At(path)
	assert(previous == "[EditorService] editor loading\n[Renderer] shader compiled")
	assert(os.is_file("/tmp/kinemium-telemetry-journal-smoke.log.pending"))
	delete(previous, runtime.heap_allocator())
	services.Telemetry_Journal_Append("[EditorService] subsequent session", "")
	services.Telemetry_Journal_Stop(false)
	assert(os.is_file("/tmp/kinemium-telemetry-journal-smoke.log.pending"))
	previous_again := services.Telemetry_Journal_Start_At(path)
	assert(previous_again == "[EditorService] editor loading\n[Renderer] shader compiled")
	delete(previous_again, runtime.heap_allocator())
	services.Telemetry_Journal_Confirm_Recovery()
	assert(!os.exists("/tmp/kinemium-telemetry-journal-smoke.log.pending"))
	services.Telemetry_Journal_Stop(true)
	assert(!os.exists(path))
	fmt.println("TELEMETRY_JOURNAL_SMOKE_PASSED")
}

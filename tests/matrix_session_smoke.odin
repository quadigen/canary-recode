package main

import "core:fmt"
import "core:os"
import "core:strings"

import engine_runtime "../src/engine/runtime"
import services "../src/engine/services"
import vm "../src/engine/vm"

run_script :: proc(script_vm: ^vm.VM, source, name: string) {
	ok, err := vm.Run(script_vm, source, name)
	if !ok {
		fmt.eprintln(err)
		delete(err)
		panic("matrix session smoke test failed")
	}
}

expect :: proc(ok: bool, message: string) {
	if !ok {
		panic(message)
	}
}

main :: proc() {
	temp_dir, temp_err := os.make_directory_temp("", "kinemium-session-*", context.allocator)
	expect(temp_err == nil, "failed to create temporary directory")

	session_path, join_err := os.join_path({temp_dir, "session.json"}, context.allocator)
	expect(join_err == nil, "failed to build session path")

	services.Matrix_Session_Path_Override = session_path

	seed := `{"homeserver":"http:
	expect(os.write_entire_file_from_string(session_path, seed) == nil, "failed to seed session")

	script_vm := vm.New()
	environment: engine_runtime.Environment
	engine_runtime.Environment_Init(&environment, &script_vm)

	descriptor := services.Find_Service(&environment.services, "MatrixService")
	expect(descriptor != nil && descriptor.object != nil, "MatrixService descriptor missing")

	matrix_service := cast(^services.MatrixService)descriptor.object
	expect(matrix_service.session != nil, "saved session was not restored")
	expect(matrix_service.session.user_id == "@saved:local", "restored userId mismatch")
	expect(matrix_service.session.access_token == "saved-token", "restored token mismatch")
	expect(matrix_service.session.device_id == "DEVICE", "restored deviceId mismatch")

	run_script(
		&script_vm,
		`
local Matrix = game:GetService("MatrixService")
assert(Matrix.Session ~= nil, "Matrix.Session nil after restore")
assert(Matrix.Session.userId == "@saved:local", "userId=" .. tostring(Matrix.Session.userId))
assert(Matrix.Session.accessToken == "saved-token")
assert(Matrix.RememberSession == true, "RememberSession should default to true")

Matrix:SetSession({ homeserver = "http:
`,
		"matrix_session_set",
	)

	data, read_err := os.read_entire_file(session_path, context.allocator)
	expect(read_err == nil, "session file missing after SetSession")
	expect(strings.contains(string(data), `"next-token"`), "SetSession did not persist the new token")
	delete(data)

	run_script(&script_vm, `game:GetService("MatrixService"):SetRememberSession(false)`, "matrix_session_disable")
	expect(!os.exists(session_path), "SetRememberSession(false) did not remove the saved session")

	run_script(&script_vm, `game:GetService("MatrixService"):SetRememberSession(true)`, "matrix_session_enable")
	expect(os.exists(session_path), "SetRememberSession(true) did not save the current session")

	run_script(&script_vm, `game:GetService("MatrixService"):SetSession(nil)`, "matrix_session_clear")
	expect(!os.exists(session_path), "SetSession(nil) did not remove the saved session")

	_ = os.remove_all(temp_dir)
	delete(session_path)
	delete(temp_dir)

	fmt.println("MATRIX_SESSION_SMOKE_PASSED")
	os.exit(0)
}

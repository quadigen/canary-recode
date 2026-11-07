package git

import "core:os"
import "core:strings"

executable: string = "git"

Result :: struct {
	exit_code: int,
	stdout:    string,
	stderr:    string,
	err:       os.Error,
}

run :: proc(args: []string, dir := "", allocator := context.allocator) -> Result {
	command := make([]string, len(args) + 1, context.temp_allocator)
	command[0] = executable
	copy(command[1:], args)

	state, out, errout, err := os.process_exec(
		os.Process_Desc{working_dir = dir, command = command},
		allocator,
	)

	return Result {
		exit_code = state.exit_code,
		stdout = string(out),
		stderr = string(errout),
		err = err,
	}
}

success :: proc(result: Result) -> bool {
	return result.err == nil && result.exit_code == 0
}

destroy_result :: proc(result: Result, allocator := context.allocator) {
	delete(result.stdout, allocator)
	delete(result.stderr, allocator)
}

run_text :: proc(
	args: []string,
	dir := "",
	allocator := context.allocator,
) -> (
	text: string,
	ok: bool,
) {
	result := run(args, dir, allocator)
	defer destroy_result(result, allocator)
	if !success(result) {
		return "", false
	}
	return strings.clone(strings.trim_space(result.stdout), allocator), true
}

is_available :: proc() -> bool {
	result := run({"--version"}, "", context.temp_allocator)
	return success(result)
}

version :: proc(allocator := context.allocator) -> (text: string, ok: bool) {
	return run_text({"--version"}, "", allocator)
}

package compositor

import "base:runtime"

Frame_Step :: enum u32 {
	Acquire,
	Claim,
	Canvas,
	Publish,
	Flush,
	Late_Acquire,
	Submit,
	Present,
}

Frame_Step_Proc :: proc "c" (_: rawptr, _: u32) -> i32

frame_flow_callback :: proc "c" (
	user: rawptr,
	step: proc "c" (_: rawptr, _: u32) -> i32,
	ending: u32,
) -> i32 {
	context = runtime.default_context()
	if user == nil || step == nil || ending > 1 {return 0}
	begin_steps := [?]Frame_Step{.Acquire, .Claim, .Canvas, .Publish}
	end_steps := [?]Frame_Step{.Flush, .Late_Acquire, .Submit, .Present}
	steps := end_steps[:] if ending != 0 else begin_steps[:]
	for phase in steps {
		if step(user, u32(phase)) != 1 {return 0}
	}
	return 1
}

package compositor

background_frame_delay :: proc(now, previous: u64, fps: int) -> u32 {
	if previous == 0 || fps <= 0 || now < previous {return 0}
	interval := u64(1_000_000_000 / fps)
	elapsed := now - previous
	if elapsed >= interval {return 0}
	return u32(clamp((interval - elapsed) / 1_000_000, 1, 4))
}

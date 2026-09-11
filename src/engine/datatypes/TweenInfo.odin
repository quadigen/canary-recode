package datatypes

import engine_enums "../enum"

TweenInfo :: struct {
	Time:            f32,
	EasingStyle:     engine_enums.EasingStyle,
	EasingDirection: engine_enums.EasingDirection,
	RepeatCount:     i32,
	Reverses:        bool,
	DelayTime:       f32,
}

TweenInfo_Default :: TweenInfo{
	Time            = 1,
	EasingStyle     = .Quad,
	EasingDirection = .Out,
	RepeatCount     = 0,
	Reverses        = false,
	DelayTime       = 0,
}

TweenInfo_New :: proc(
	time: f32,
	easing_style: engine_enums.EasingStyle = .Quad,
	easing_direction: engine_enums.EasingDirection = .Out,
	repeat_count: i32 = 0,
	reverses: bool = false,
	delay_time: f32 = 0,
) -> (TweenInfo, bool) {
	if time < 0 || time != time ||
	   delay_time < 0 || delay_time != delay_time ||
	   repeat_count < -1 {
		return TweenInfo{}, false
	}

	return TweenInfo{
		Time            = time,
		EasingStyle     = easing_style,
		EasingDirection = easing_direction,
		RepeatCount     = repeat_count,
		Reverses        = reverses,
		DelayTime       = delay_time,
	}, true
}

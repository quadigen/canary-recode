package datatypes

import "core:slice"

ColorSequenceKeypoint :: struct {
	Time:  f32,
	Value: Color3,
}

ColorSequenceKeypoint_New :: proc(time: f32, value: Color3) -> ColorSequenceKeypoint {
	return ColorSequenceKeypoint{time, value}
}

ColorSequenceKeypoint_Equal :: proc(a, b: ColorSequenceKeypoint) -> bool {
	return a.Time == b.Time && a.Value == b.Value
}

ColorSequence :: struct {
	Keypoints: []ColorSequenceKeypoint,
}

ColorSequence_New :: proc(color: Color3) -> ColorSequence {
	keypoints := make([]ColorSequenceKeypoint, 2)
	keypoints[0] = ColorSequenceKeypoint{0, color}
	keypoints[1] = ColorSequenceKeypoint{1, color}
	return ColorSequence{keypoints}
}

ColorSequence_New2 :: proc(color0, color1: Color3) -> ColorSequence {
	keypoints := make([]ColorSequenceKeypoint, 2)
	keypoints[0] = ColorSequenceKeypoint{0, color0}
	keypoints[1] = ColorSequenceKeypoint{1, color1}
	return ColorSequence{keypoints}
}

ColorSequence_Clone :: proc(sequence: ColorSequence) -> ColorSequence {
	return ColorSequence{slice.clone(sequence.Keypoints)}
}

ColorSequence_FromKeypoints :: proc(keypoints: []ColorSequenceKeypoint) -> (ColorSequence, bool) {
	if len(keypoints) < 2 {
		return ColorSequence{}, false
	}
	for keypoint, i in keypoints {
		if keypoint.Time != keypoint.Time || keypoint.Time < 0 || keypoint.Time > 1 {
			return ColorSequence{}, false
		}
		if i > 0 && keypoints[i-1].Time >= keypoint.Time {
			return ColorSequence{}, false
		}
	}

	if keypoints[0].Time != 0 || keypoints[len(keypoints)-1].Time != 1 {
		return ColorSequence{}, false
	}

	return ColorSequence{slice.clone(keypoints)}, true
}

ColorSequence_Destroy :: proc(sequence: ColorSequence) {
	delete(sequence.Keypoints)
}

ColorSequence_Equal :: proc(a, b: ColorSequence) -> bool {
	if len(a.Keypoints) != len(b.Keypoints) {
		return false
	}
	for i in 0 ..< len(a.Keypoints) {
		if !ColorSequenceKeypoint_Equal(a.Keypoints[i], b.Keypoints[i]) {
			return false
		}
	}
	return true
}

ColorSequence_At :: proc(sequence: ColorSequence, time: f32) -> Color3 {
	keypoints := sequence.Keypoints
	if len(keypoints) == 0 {
		return Color3{}
	}

	t := clamp(time, 0, 1)

	if t <= keypoints[0].Time {
		return keypoints[0].Value
	}
	if t >= keypoints[len(keypoints)-1].Time {
		return keypoints[len(keypoints)-1].Value
	}

	for i in 0 ..< len(keypoints) - 1 {
		current := keypoints[i]
		next := keypoints[i+1]
		if t >= current.Time && t <= next.Time {
			span := next.Time - current.Time
			alpha: f32 = 0
			if span > 0 {
				alpha = (t - current.Time) / span
			}
			return Lerp(current.Value, next.Value, alpha)
		}
	}

	return keypoints[len(keypoints)-1].Value
}


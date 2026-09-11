package datatypes

import "core:slice"

NumberSequenceKeypoint :: struct {
	Time:     f32,
	Value:    f32,
	Envelope: f32,
}

NumberSequenceKeypoint_New :: proc(time, value: f32, envelope: f32 = 0) -> NumberSequenceKeypoint {
	return NumberSequenceKeypoint{
		Time     = time,
		Value    = value,
		Envelope = max(envelope, 0),
	}
}

NumberSequenceKeypoint_Equal :: proc(a, b: NumberSequenceKeypoint) -> bool {
	return a.Time == b.Time &&
	       a.Value == b.Value &&
	       a.Envelope == b.Envelope
}

NumberSequence :: struct {
	Keypoints: []NumberSequenceKeypoint,
}

NumberSequence_New :: proc(value: f32) -> NumberSequence {
	keypoints := make([]NumberSequenceKeypoint, 2)
	keypoints[0] = NumberSequenceKeypoint_New(0, value)
	keypoints[1] = NumberSequenceKeypoint_New(1, value)
	return NumberSequence{Keypoints = keypoints}
}

NumberSequence_New2 :: proc(start, finish: f32) -> NumberSequence {
	keypoints := make([]NumberSequenceKeypoint, 2)
	keypoints[0] = NumberSequenceKeypoint_New(0, start)
	keypoints[1] = NumberSequenceKeypoint_New(1, finish)
	return NumberSequence{Keypoints = keypoints}
}

NumberSequence_Clone :: proc(sequence: NumberSequence) -> NumberSequence {
	return NumberSequence{Keypoints = slice.clone(sequence.Keypoints)}
}

NumberSequence_FromKeypoints :: proc(keypoints: []NumberSequenceKeypoint) -> (NumberSequence, bool) {
	if len(keypoints) < 2 {
		return NumberSequence{}, false
	}

	for keypoint, i in keypoints {
		if keypoint.Time != keypoint.Time ||
		   keypoint.Value != keypoint.Value ||
		   keypoint.Envelope != keypoint.Envelope ||
		   keypoint.Time < 0 ||
		   keypoint.Time > 1 ||
		   keypoint.Envelope < 0 {
			return NumberSequence{}, false
		}

		if i > 0 && keypoints[i-1].Time >= keypoint.Time {
			return NumberSequence{}, false
		}
	}

	if keypoints[0].Time != 0 ||
	   keypoints[len(keypoints)-1].Time != 1 {
		return NumberSequence{}, false
	}

	return NumberSequence{Keypoints = slice.clone(keypoints)}, true
}

NumberSequence_Destroy :: proc(sequence: NumberSequence) {
	delete(sequence.Keypoints)
}

NumberSequence_Equal :: proc(a, b: NumberSequence) -> bool {
	if len(a.Keypoints) != len(b.Keypoints) {
		return false
	}

	for i in 0 ..< len(a.Keypoints) {
		if !NumberSequenceKeypoint_Equal(a.Keypoints[i], b.Keypoints[i]) {
			return false
		}
	}

	return true
}

NumberSequence_At :: proc(sequence: NumberSequence, time: f32) -> (value, envelope: f32) {
	if len(sequence.Keypoints) == 0 {
		return 0, 0
	}

	t := clamp(time, 0, 1)

	if t <= sequence.Keypoints[0].Time {
		k := sequence.Keypoints[0]
		return k.Value, k.Envelope
	}

	last := sequence.Keypoints[len(sequence.Keypoints)-1]
	if t >= last.Time {
		return last.Value, last.Envelope
	}

	for i in 0 ..< len(sequence.Keypoints)-1 {
		a := sequence.Keypoints[i]
		b := sequence.Keypoints[i+1]

		if t >= a.Time && t <= b.Time {
			span := b.Time - a.Time
			alpha: f32 = 0
			if span > 0 {
				alpha = (t - a.Time) / span
			}

			value := a.Value + (b.Value-a.Value)*alpha
			envelope := a.Envelope + (b.Envelope-a.Envelope)*alpha
			return value, envelope
		}
	}

	return last.Value, last.Envelope
}

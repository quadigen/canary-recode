package datatypes

Faces :: struct {
	Top:    bool,
	Bottom: bool,
	Left:   bool,
	Right:  bool,
	Front:  bool,
	Back:   bool,
}

Faces_None :: Faces{}
Faces_All  :: Faces{true, true, true, true, true, true}

package datatypes

Axes :: struct {
	X: bool,
	Y: bool,
	Z: bool,
}

Axes_None :: Axes{}
Axes_All  :: Axes{true, true, true}

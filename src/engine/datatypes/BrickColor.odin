package datatypes

BrickColor :: struct {
	number: i32,
	color:  Color3,
	name:   string,
}

BrickColor_White :: BrickColor{1, Color3{0.9725, 0.9725, 0.9725}, "White"}
BrickColor_Black :: BrickColor{26, Color3{0.1059, 0.1647, 0.2078}, "Black"}
BrickColor_Red   :: BrickColor{21, Color3{0.7686, 0.1569, 0.1098}, "Bright red"}
BrickColor_Blue  :: BrickColor{23, Color3{0.05098, 0.4118, 0.6745}, "Bright blue"}
BrickColor_Green :: BrickColor{37, Color3{0.1961, 0.5882, 0.3373}, "Bright green"}
BrickColor_Gray  :: BrickColor{194, Color3{0.6314, 0.6353, 0.6471}, "Medium stone grey"}

BrickColor_From_Number :: proc(number: i32) -> BrickColor {
	switch number {
	case BrickColor_White.number: return BrickColor_White
	case BrickColor_Black.number: return BrickColor_Black
	case BrickColor_Red.number:   return BrickColor_Red
	case BrickColor_Blue.number:  return BrickColor_Blue
	case BrickColor_Green.number: return BrickColor_Green
	case BrickColor_Gray.number:  return BrickColor_Gray
	}
	return BrickColor{number, BrickColor_Gray.color, BrickColor_Gray.name}
}

BrickColor_From_Name :: proc(name: string) -> BrickColor {
	switch name {
	case "white":         return BrickColor_White
	case "White":         return BrickColor_White
	case "black":         return BrickColor_Black
	case "Black":         return BrickColor_Black
	case "bright red":    return BrickColor_Red
	case "Bright red":    return BrickColor_Red
	case "bright blue":   return BrickColor_Blue
	case "Bright blue":   return BrickColor_Blue
	case "bright green":  return BrickColor_Green
	case "Bright green":  return BrickColor_Green
	case "medium stone grey", "medium stone gray":
		return BrickColor_Gray
	case "Medium stone grey", "Medium stone gray":
		return BrickColor_Gray
	}
	return BrickColor_Gray
}

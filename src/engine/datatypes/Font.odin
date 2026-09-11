package datatypes

import "core:strings"
import engine_enums "../enum"

Font :: struct {
	Family: string,
	Weight: engine_enums.FontWeight,
	Style:  engine_enums.FontStyle,
}

Font_New :: proc(
	family: string,
	weight: engine_enums.FontWeight = .Regular,
	style: engine_enums.FontStyle = .Normal,
) -> Font {
	return Font{
		Family = strings.clone(family),
		Weight = weight,
		Style  = style,
	}
}

Font_Clone :: proc(font: Font) -> Font {
	return Font_New(font.Family, font.Weight, font.Style)
}

Font_Destroy :: proc(font: ^Font) {
	if font == nil {
		return
	}
	delete(font.Family)
	font.Family = ""
}

package datatypes

import engine_enums "../enum"
import "core:fmt"
import "core:strings"
import "core:sync"


MEMORY_FONT_PREFIX :: "memory://"


memory_font_counter: int

Font :: struct {
	Family: string,
	Weight: engine_enums.FontWeight,
	Style:  engine_enums.FontStyle,
	Data:   []u8,
}

Font_New :: proc(
	family: string,
	weight: engine_enums.FontWeight = .Regular,
	style: engine_enums.FontStyle = .Normal,
) -> Font {
	return Font{Family = strings.clone(family), Weight = weight, Style = style}
}


Font_From_Memory :: proc(
	data: []u8,
	weight: engine_enums.FontWeight = .Regular,
	style: engine_enums.FontStyle = .Normal,
) -> (
	Font,
	bool,
) {
	if len(data) == 0 {
		return {}, false
	}

	owned := make([]u8, len(data))
	if owned == nil {
		return {}, false
	}
	copy(owned, data)


	id := sync.atomic_add(&memory_font_counter, 1)

	return Font {
			Family = strings.clone(fmt.tprintf("%v%d", MEMORY_FONT_PREFIX, id)),
			Weight = weight,
			Style = style,
			Data = owned,
		},
		true
}


Font_Has_Memory :: proc(font: Font) -> bool {
	return len(font.Data) > 0
}

Font_Clone :: proc(font: Font) -> Font {
	result := Font_New(font.Family, font.Weight, font.Style)

	if len(font.Data) > 0 {
		owned := make([]u8, len(font.Data))
		if owned != nil {
			copy(owned, font.Data)
			result.Data = owned
		}
	}

	return result
}

Font_From_Enum :: proc(font: engine_enums.Font) -> Font {
	family := "SourceSans"
	weight := engine_enums.FontWeight.Regular
	style := engine_enums.FontStyle.Normal

	#partial switch font {
	case .SourceSansBold,
	     .GothamBold,
	     .FredokaOneBold,
	     .GrenzeGotischBold,
	     .MontserratBold,
	     .MontserratSemibold,
	     .OpenSansBold,
	     .OpenSansSemibold,
	     .ArialBold,
	     .ArimoBold,
	     .SourceCodeProBold,
	     .SourceCodeProSemibold,
	     .NotoSansBold,
	     .NotoMonoBold,
	     .NotoSerifBold,
	     .NotoSansDisplayBold,
	     .NotoSerifDisplayBold,
	     .NotoSansSCBold,
	     .NotoSerifSCBold:
		weight = .Bold
	case .SourceSansLight:
		weight = .Light
	case .SourceSansItalic,
	     .NotoSansItalic,
	     .NotoSerifItalic,
	     .OpenSansItalic,
	     .SourceCodeProItalic,
	     .ArialBoldItalic:
		style = .Italic
	case .NotoSans,
	     .NotoSerif,
	     .NotoMono,
	     .NotoSansMono,
	     .NotoSansDisplay,
	     .NotoSerifDisplay,
	     .NotoSansSC,
	     .NotoSerifSC,
	     .Montserrat,
	     .OpenSans,
	     .SourceCodePro:
		family = "NotoSans"
	case .BuilderSans:
		family = "SourceSans"
	}

	return Font_New(family, weight, style)
}

Font_Destroy :: proc(font: ^Font) {
	if font == nil {
		return
	}
	delete(font.Family)
	font.Family = ""


	if len(font.Data) > 0 {
		delete(font.Data)
		font.Data = nil
	}
}

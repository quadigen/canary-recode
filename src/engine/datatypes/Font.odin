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
}

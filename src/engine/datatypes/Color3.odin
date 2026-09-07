package datatypes
import "core:math"
import "core:fmt"

Color3 :: struct {
    R, G, B: f32,
}

ToRGB :: proc(c: Color3) -> (f32, f32, f32) {
    return c.R * 255.0, c.G * 255.0, c.B * 255.0
}

New :: proc(r, g, b: f32 ) -> Color3 {
	return Color3{r, g, b}
}

FromRGB :: proc(r, g, b: f32) -> Color3 {
	return Color3{
		R = r / 255.0,
		G = g / 255.0,
		B = b / 255.0,
	}
}

FromHSV :: proc(hue, saturation, value: f32) -> Color3 {
	h := hue - math.floor(hue)
	s := saturation
	v := value

	if s == 0 {
		return Color3{v, v, v}
	}

	h6 := h * 6.0
	sector := int(math.floor(h6))
	f := h6 - f32(sector)

	p := v * (1.0 - s)
	q := v * (1.0 - s * f)
	t := v * (1.0 - s * (1.0 - f))

	switch sector % 6 {
	case 0:
		return Color3{v, t, p}
	case 1:
		return Color3{q, v, p}
	case 2:
		return Color3{p, v, t}
	case 3:
		return Color3{p, q, v}
	case 4:
		return Color3{t, p, v}
	case 5:
		return Color3{v, p, q}
	}

	return Color3{}
}

Lerp :: proc(c, goal: Color3, alpha: f32) -> Color3 {
	return Color3{
		R = c.R + (goal.R - c.R) * alpha,
		G = c.G + (goal.G - c.G) * alpha,
		B = c.B + (goal.B - c.B) * alpha,
	}
}

ToHSV :: proc(c: Color3) -> (h, s, v: f32) {
	max_component := max(c.R, max(c.G, c.B))
	min_component := min(c.R, min(c.G, c.B))
	delta := max_component - min_component

	v = max_component

	if max_component == 0 {
		s = 0
	} else {
		s = delta / max_component
	}

	if delta == 0 {
		h = 0
		return
	}

	if max_component == c.R {
		h = (c.G - c.B) / delta

		if h < 0 {
			h += 6.0
		}
	} else if max_component == c.G {
		h = (c.B - c.R) / delta + 2.0
	} else {
		h = (c.R - c.G) / delta + 4.0
	}

	h /= 6.0
	return
}

hex_digit :: proc(c: u8) -> (u8, bool) {
	if c >= '0' && c <= '9' {
		return c - '0', true
	}

	if c >= 'a' && c <= 'f' {
		return c - 'a' + 10, true
	}

	if c >= 'A' && c <= 'F' {
		return c - 'A' + 10, true
	}

	return 0, false
}

FromHex :: proc(hex: string) -> (Color3, bool) {
	hex := hex

	if len(hex) > 0 && hex[0] == '#' {
		hex = hex[1:]
	}

	if len(hex) == 3 {
		r, ok_r := hex_digit(hex[0])
		g, ok_g := hex_digit(hex[1])
		b, ok_b := hex_digit(hex[2])

		if !ok_r || !ok_g || !ok_b {
			return Color3{}, false
		}

		return FromRGB(
			f32(r * 17),
			f32(g * 17),
			f32(b * 17),
		), true
	}

	if len(hex) == 6 {
		r1, ok_r1 := hex_digit(hex[0])
		r2, ok_r2 := hex_digit(hex[1])
		g1, ok_g1 := hex_digit(hex[2])
		g2, ok_g2 := hex_digit(hex[3])
		b1, ok_b1 := hex_digit(hex[4])
		b2, ok_b2 := hex_digit(hex[5])

		if !ok_r1 || !ok_r2 ||
		   !ok_g1 || !ok_g2 ||
		   !ok_b1 || !ok_b2 {
			return Color3{}, false
		}

		r := r1 * 16 + r2
		g := g1 * 16 + g2
		b := b1 * 16 + b2

		return FromRGB(f32(r), f32(g), f32(b)), true
	}

	return Color3{}, false
}

ToHex :: proc(c: Color3) -> string {
	r := int(math.round(clamp(c.R, 0.0, 1.0) * 255.0))
	g := int(math.round(clamp(c.G, 0.0, 1.0) * 255.0))
	b := int(math.round(clamp(c.B, 0.0, 1.0) * 255.0))

	return fmt.tprintf("%02x%02x%02x", r, g, b)
}
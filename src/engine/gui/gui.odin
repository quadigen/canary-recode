package gui

import "core:math"

import kineffi "../bindings"
import datatypes "../datatypes"

Rect :: struct {
	x:              f32,
	y:              f32,
	width:          f32,
	height:         f32,
	color:          datatypes.Color3,
	bgTransparency: f32,
}

TextParams :: struct {
	x:            f32,
	y:            f32,
	TextSize:     f32,
	color:        datatypes.Color3,
	transparency: f32,

	font:     cstring,
	typeface: ^kineffi.KineSkiaTypeface,
}

ShadowParams :: struct {
	offsetX:   f32,
	offsetY:   f32,
	blurSigma: f32,
	spread:    f32,
	color:     datatypes.Color3,
	alpha:     f32,
}

colorToU8 :: proc(color: datatypes.Color3) -> (u8, u8, u8) {
	r := u8(math.round(clamp(color.R, 0, 1) * 255))
	g := u8(math.round(clamp(color.G, 0, 1) * 255))
	b := u8(math.round(clamp(color.B, 0, 1) * 255))
	return r, g, b
}

alphaToU8 :: proc(transparency: f32) -> u8 {
	return u8(math.round((1 - clamp(transparency, 0, 1)) * 255))
}

drawRect :: proc(surface: ^kineffi.KineSkiaSurface, rect: Rect) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawRect(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		r,
		g,
		b,
		a,
		0,
	)
}

drawRectStroke :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	strokeWidth: f32,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawRect(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		r,
		g,
		b,
		a,
		strokeWidth,
	)
}

drawRoundedRect :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	cornerRadius: f32,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawRoundRect(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		cornerRadius,
		cornerRadius,
		r,
		g,
		b,
		a,
		0,
	)
}

drawRoundedRectStroke :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	cornerRadius: f32,
	strokeWidth: f32,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawRoundRect(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		cornerRadius,
		cornerRadius,
		r,
		g,
		b,
		a,
		strokeWidth,
	)
}

drawSquircle :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	radius: f32,
	exponent: f32 = 4,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawSquircle(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		radius,
		exponent,
		r,
		g,
		b,
		a,
		0,
	)
}

drawRotatedRect :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	rotation: f32,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawRotatedRect(
		surface,
		rect.x + rect.width / 2,
		rect.y + rect.height / 2,
		rect.width,
		rect.height,
		rotation,
		r,
		g,
		b,
		a,
		0,
	)
}

drawCircle :: proc(
	surface: ^kineffi.KineSkiaSurface,
	x, y, radius: f32,
	color: datatypes.Color3,
	transparency: f32 = 0,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(color)
	a := alphaToU8(transparency)

	kineffi.Kine_Skia_Surface_DrawCircle(
		surface,
		x,
		y,
		radius,
		r,
		g,
		b,
		a,
		0,
	)
}

drawOval :: proc(surface: ^kineffi.KineSkiaSurface, rect: Rect) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawOval(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		r,
		g,
		b,
		a,
		0,
	)
}

drawArc :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	startAngle: f32,
	sweepAngle: f32,
	useCenter: bool = false,
	strokeWidth: f32 = 1,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawArc(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		startAngle,
		sweepAngle,
		i32(useCenter),
		r,
		g,
		b,
		a,
		strokeWidth,
	)
}

drawLine :: proc(
	surface: ^kineffi.KineSkiaSurface,
	x0, y0, x1, y1: f32,
	width: f32,
	color: datatypes.Color3,
	transparency: f32 = 0,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(color)
	a := alphaToU8(transparency)

	kineffi.Kine_Skia_Surface_DrawLine(
		surface,
		x0,
		y0,
		x1,
		y1,
		width,
		r,
		g,
		b,
		a,
	)
}

drawShadow :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	radius: f32,
	exponent: f32,
	shadow: ShadowParams,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(shadow.color)
	a := u8(math.round(clamp(shadow.alpha, 0, 1) * 255))

	kineffi.Kine_Skia_Surface_DrawUIShadow(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		radius,
		exponent,
		shadow.offsetX,
		shadow.offsetY,
		shadow.blurSigma,
		shadow.spread,
		r,
		g,
		b,
		a,
	)
}

drawBackdropBlur :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	cornerRadius: f32,
	blurSigma: f32,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(rect.color)
	a := alphaToU8(rect.bgTransparency)

	kineffi.Kine_Skia_Surface_DrawBackdropBlurRect(
		surface,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		cornerRadius,
		cornerRadius,
		blurSigma,
		a,
		r,
		g,
		b,
		a,
	)
}

drawText :: proc(
	surface: ^kineffi.KineSkiaSurface,
	text: cstring,
	params: TextParams,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(params.color)
	a := alphaToU8(params.transparency)

	if params.typeface != nil {
		kineffi.Kine_Skia_Surface_DrawTextTypeface(
			surface,
			text,
			params.x,
			params.y,
			params.TextSize,
			params.typeface,
			r,
			g,
			b,
			a,
		)

		return
	}

	kineffi.Kine_Skia_Surface_DrawText(
		surface,
		text,
		params.x,
		params.y,
		params.TextSize,
		params.font,
		r,
		g,
		b,
		a,
	)
}

drawTextShadow :: proc(
	surface: ^kineffi.KineSkiaSurface,
	text: cstring,
	params: TextParams,
	shadow: ShadowParams,
) {
	if surface == nil {
		return
	}

	r, g, b := colorToU8(shadow.color)

	a := u8(
		math.round(
			clamp(shadow.alpha, 0, 1) * 255,
		),
	)

	if params.typeface != nil {
		kineffi.Kine_Skia_Surface_DrawTextShadowTypeface(
			surface,
			text,
			params.x,
			params.y,
			params.TextSize,
			params.typeface,

			shadow.offsetX,
			shadow.offsetY,
			shadow.blurSigma,
			shadow.spread,

			r,
			g,
			b,
			a,
		)

		return
	}

	kineffi.Kine_Skia_Surface_DrawTextShadow(
		surface,
		text,
		params.x,
		params.y,
		params.TextSize,
		params.font,

		shadow.offsetX,
		shadow.offsetY,
		shadow.blurSigma,
		shadow.spread,

		r,
		g,
		b,
		a,
	)
}

measureText :: proc(
	text: cstring,
	fontSize: f32,
	font: cstring,
) -> f32 {
	return kineffi.Kine_Skia_Surface_MeasureText(
		text,
		fontSize,
		font,
	)
}

getFontLineHeight :: proc(fontSize: f32, font: cstring) -> f32 {
	return kineffi.Kine_Skia_Surface_GetFontLineHeight(fontSize, font)
}

getFontAscent :: proc(fontSize: f32, font: cstring) -> f32 {
	return kineffi.Kine_Skia_Surface_GetFontAscent(fontSize, font)
}

drawImage :: proc(
	surface: ^kineffi.KineSkiaSurface,
	imageObject: ^kineffi.KineSkiaImage,
	x, y: f32,
	transparency: f32 = 0,
) {
	if surface == nil || imageObject == nil {
		return
	}

	kineffi.Kine_Skia_Surface_DrawImage(
		surface,
		imageObject,
		x,
		y,
		alphaToU8(transparency),
	)
}

drawImageSized :: proc(
	surface: ^kineffi.KineSkiaSurface,
	imageObject: ^kineffi.KineSkiaImage,
	rect: Rect,
) {
	if surface == nil || imageObject == nil {
		return
	}

	kineffi.Kine_Skia_Surface_DrawImageSized(
		surface,
		imageObject,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		alphaToU8(rect.bgTransparency),
	)
}

drawImageShadow :: proc(
	surface: ^kineffi.KineSkiaSurface,
	imageObject: ^kineffi.KineSkiaImage,
	rect: Rect,
	shadow: ShadowParams,
) {
	if surface == nil || imageObject == nil {
		return
	}

	r, g, b := colorToU8(shadow.color)
	a := u8(math.round(clamp(shadow.alpha, 0, 1) * 255))

	kineffi.Kine_Skia_Surface_DrawImageShadow(
		surface,
		imageObject,
		rect.x,
		rect.y,
		rect.width,
		rect.height,
		shadow.offsetX,
		shadow.offsetY,
		shadow.blurSigma,
		shadow.spread,
		r,
		g,
		b,
		a,
	)
}

drawImageRect :: proc(
	surface: ^kineffi.KineSkiaSurface,
	imageObject: ^kineffi.KineSkiaImage,
	src: Rect,
	dst: Rect,
) {
	if surface == nil || imageObject == nil {
		return
	}

	kineffi.Kine_Skia_Surface_DrawImageRect(
		surface,
		imageObject,
		src.x,
		src.y,
		src.width,
		src.height,
		dst.x,
		dst.y,
		dst.width,
		dst.height,
		alphaToU8(dst.bgTransparency),
	)
}

save :: proc(surface: ^kineffi.KineSkiaSurface) {
	if surface != nil {
		kineffi.Kine_Skia_Surface_Save(surface)
	}
}

restore :: proc(surface: ^kineffi.KineSkiaSurface) {
	if surface != nil {
		kineffi.Kine_Skia_Surface_Restore(surface)
	}
}

translate :: proc(surface: ^kineffi.KineSkiaSurface, x, y: f32) {
	if surface != nil {
		kineffi.Kine_Skia_Surface_Translate(surface, x, y)
	}
}

rotate :: proc(surface: ^kineffi.KineSkiaSurface, degrees: f32) {
	if surface != nil {
		kineffi.Kine_Skia_Surface_Rotate(surface, degrees)
	}
}

scale :: proc(surface: ^kineffi.KineSkiaSurface, x, y: f32) {
	if surface != nil {
		kineffi.Kine_Skia_Surface_Scale(surface, x, y)
	}
}

clipRect :: proc(surface: ^kineffi.KineSkiaSurface, rect: Rect) {
	if surface != nil {
		kineffi.Kine_Skia_Surface_ClipRect(
			surface,
			rect.x,
			rect.y,
			rect.width,
			rect.height,
		)
	}
}

clipRoundedRect :: proc(
	surface: ^kineffi.KineSkiaSurface,
	rect: Rect,
	cornerRadius: f32,
) {
	if surface != nil {
		kineffi.Kine_Skia_Surface_ClipRoundRect(
			surface,
			rect.x,
			rect.y,
			rect.width,
			rect.height,
			cornerRadius,
			cornerRadius,
		)
	}
}

package datatypes

import assetstore "../assetstore"
import "core:slice"
import "core:strings"

Animated :: struct {
	uri: string,
}

Animated_From_URI :: proc(uri: string) -> Animated {
	return Animated{uri = strings.clone(uri)}
}

Animated_Clone :: proc(value: Animated) -> Animated {
	return Animated_From_URI(value.uri)
}

Animated_Format :: proc(data: []u8) -> string {
	if len(data) >= 6 {
		if string(data[:6]) == "GIF87a" || string(data[:6]) == "GIF89a" {return "gif"}
		if data[4] == 0xe0 && data[5] == 0xa5 {return "aseprite"}
	}
	return ""
}

Animated_From_Bytes :: proc(data: []u8) -> (Animated, bool) {
	format := Animated_Format(data)
	if format == "" || len(data) > 32 * 1024 * 1024 {return {}, false}
	path := "animation.gif" if format == "gif" else "animation.aseprite"
	id := assetstore.Register(slice.clone(data), path, .Texture)
	defer delete(id)
	if id == "" {return {}, false}
	return Animated{uri = assetstore.Make_Uri(id)}, true
}

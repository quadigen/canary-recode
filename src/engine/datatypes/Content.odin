package datatypes

import "core:strings"

Content :: struct {
	uri: string,
}

Content_From_URI :: proc(uri: string) -> Content {
	return Content{strings.clone(uri)}
}

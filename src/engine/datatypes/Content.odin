package datatypes

import "core:strings"

Content :: struct {
	uri:        string,
	object_id:  u32,
	object_kind: u8,
}

Content_From_URI :: proc(uri: string) -> Content {
	return Content{uri = strings.clone(uri)}
}

Content_From_Object :: proc(object: rawptr) -> Content {
	content := Content{}
	if content_object_resolver != nil {
		id, kind := content_object_resolver(object)
		if id != 0 {
			content.object_id = id
			content.object_kind = kind
		}
	}
	return content
}

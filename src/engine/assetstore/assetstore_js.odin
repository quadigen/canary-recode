#+build js

package assetstore

Read_Asset_File :: proc(path: string) -> ([]u8, bool) {
	return nil, false
}

Materialize :: proc(id: string) -> (string, bool) {
	return "", false
}

Purge_Cache :: proc() -> bool {
	return true
}

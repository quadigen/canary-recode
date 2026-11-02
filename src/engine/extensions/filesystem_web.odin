#+build js

package extensions

platform_library_candidates :: proc(directory: string) -> []string {
	return nil
}

Manifest_Load :: proc(directory: string) -> (manifest: Manifest, err: string) {
	return {}, "native extensions are not supported on this platform"
}

Discover :: proc(context_state: ^Context, directory: string) -> (loaded: int, err: string) {
	return 0, "native extensions are not supported on this platform"
}

@(private)
resolve_library_path :: proc(manifest: ^Manifest) -> (string, string) {
	return "", "native extensions are not supported on this platform"
}

#+build linux:android
package main

import "base:runtime"

@(export, link_name="SDL_main")
android_main :: proc "c" (argc: i32, argv: ^^u8) -> i32 {
	context = runtime.default_context()
	main()
	return 0
}

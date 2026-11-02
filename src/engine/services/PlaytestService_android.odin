#+build linux:android
package services

import "core:strings"

when #config(KINE_ANDROID, false) {
	foreign import sdlandroid "libSDL3.so"


	foreign sdlandroid {
		@(link_name = "SDL_GetAndroidJNIEnv")
		sdl_get_android_jni_env :: proc() -> rawptr ---
		@(link_name = "SDL_GetAndroidActivity")
		sdl_get_android_activity :: proc() -> rawptr ---
	}


	JNI_GET_OBJECT_CLASS :: 31
	JNI_GET_STATIC_METHOD_ID :: 113
	JNI_CALL_STATIC_VOID_METH_A :: 143
	JNI_NEW_STRING_UTF :: 167


	jni_value :: struct #align (8) {
		reference: rawptr,
	}

	jni_table :: proc(env: rawptr) -> [^]rawptr {
		return cast([^]rawptr)(cast(^rawptr)env)^
	}

	jni_get_object_class :: proc(env, object: rawptr) -> rawptr {
		call := transmute(proc "c" (e, o: rawptr) -> rawptr)jni_table(env)[JNI_GET_OBJECT_CLASS]
		return call(env, object)
	}

	jni_get_static_method :: proc(env: rawptr, class: rawptr, name, signature: cstring) -> rawptr {
		call := transmute(proc "c" (e, c: rawptr, n, s: cstring) -> rawptr)jni_table(env)[JNI_GET_STATIC_METHOD_ID]
		return call(env, class, name, signature)
	}

	jni_new_string_utf :: proc(env: rawptr, value: cstring) -> rawptr {
		call := transmute(proc "c" (e: rawptr, v: cstring) -> rawptr)jni_table(env)[JNI_NEW_STRING_UTF]
		return call(env, value)
	}

	jni_call_static_void_a :: proc(env, class, method: rawptr, values: [^]jni_value) {
		call := transmute(proc "c" (e, c, m: rawptr, v: [^]jni_value))jni_table(env)[JNI_CALL_STATIC_VOID_METH_A]
		call(env, class, method, values)
	}


	android_playtest_launch :: proc(args: []string) -> (failure: string, ok: bool) {
		env := sdl_get_android_jni_env()
		activity := sdl_get_android_activity()
		if env == nil || activity == nil {
			return "the Android activity is unavailable", false
		}

		joined := strings.join(args, "\n")
		defer delete(joined)


		joined_c := strings.clone_to_cstring(joined, context.temp_allocator)

		class := jni_get_object_class(env, activity)
		if class == nil {
			return "could not resolve the Android activity class", false
		}

		method := jni_get_static_method(
			env,
			class,
			"launchPlaytest",
			"(Landroid/content/Context;Ljava/lang/String;)V",
		)
		if method == nil {
			return "the Android playtest launcher is missing", false
		}

		text := jni_new_string_utf(env, joined_c)
		if text == nil {
			return "could not marshal the Android playtest arguments", false
		}

		values := [2]jni_value{{reference = activity}, {reference = text}}
		jni_call_static_void_a(env, class, method, &values[0])
		return "", true
	}


	android_playtest_stop :: proc() -> bool {
		env := sdl_get_android_jni_env()
		activity := sdl_get_android_activity()
		if env == nil || activity == nil {
			return false
		}

		class := jni_get_object_class(env, activity)
		if class == nil {
			return false
		}

		method := jni_get_static_method(env, class, "stopPlaytest", "(Landroid/content/Context;)V")
		if method == nil {
			return false
		}

		values := [1]jni_value{{reference = activity}}
		jni_call_static_void_a(env, class, method, &values[0])
		return true
	}
}

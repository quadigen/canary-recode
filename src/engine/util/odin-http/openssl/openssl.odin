package openssl

import "core:c"
import "core:c/libc"

SHARED :: #config(OPENSSL_SHARED, false)

when ODIN_OS == .Windows {
	when SHARED {
		foreign import lib {"./includes/windows/libssl.lib", "./includes/windows/libcrypto.lib"}
	} else {

		foreign import lib {"./includes/windows/libssl_static.lib", "./includes/windows/libcrypto_static.lib", "system:ws2_32.lib", "system:gdi32.lib", "system:advapi32.lib", "system:crypt32.lib", "system:user32.lib"}
	}
} else when ODIN_OS == .Darwin {
	foreign import lib {"system:ssl.3", "system:crypto.3"}
} else {
	foreign import lib {"system:libssl.so.3", "system:libcrypto.so.3"}
}

Version :: bit_field u32 {
	pre_release: uint | 4,
	patch:       uint | 16,
	minor:       uint | 8,
	major:       uint | 4,
}

VERSION: Version

@(private, init)
version_check :: proc "contextless" () {
	VERSION = Version(OpenSSL_version_num())
	assert_contextless(VERSION.major == 3, "invalid OpenSSL library version, expected 3.x")
}

SSL_METHOD :: struct {}
SSL_CTX :: struct {}
SSL :: struct {}
X509_VERIFY_PARAM :: struct {}
SSL_VERIFY_PEER :: 1
SSL_ERROR_SSL :: c.int(1)
SSL_ERROR_WANT_READ :: c.int(2)
SSL_ERROR_WANT_WRITE :: c.int(3)
SSL_ERROR_SYSCALL :: c.int(5)
SSL_ERROR_ZERO_RETURN :: c.int(6)

SSL_CTRL_SET_TLSEXT_HOSTNAME :: 55

TLSEXT_NAMETYPE_host_name :: 0

foreign lib {
	TLS_client_method :: proc() -> ^SSL_METHOD ---
	SSL_CTX_new :: proc(method: ^SSL_METHOD) -> ^SSL_CTX ---
	SSL_new :: proc(ctx: ^SSL_CTX) -> ^SSL ---
	SSL_CTX_set_default_verify_paths :: proc(ctx: ^SSL_CTX) -> c.int ---
	SSL_CTX_set_verify :: proc(ctx: ^SSL_CTX, mode: c.int, callback: rawptr) ---
	SSL_set1_host :: proc(ssl: ^SSL, hostname: cstring) -> c.int ---
	SSL_get0_param :: proc(ssl: ^SSL) -> ^X509_VERIFY_PARAM ---
	X509_VERIFY_PARAM_set1_ip_asc :: proc(param: ^X509_VERIFY_PARAM, ip: cstring) -> c.int ---
	SSL_get_verify_result :: proc(ssl: ^SSL) -> c.long ---
	SSL_set_fd :: proc(ssl: ^SSL, fd: c.int) -> c.int ---
	SSL_connect :: proc(ssl: ^SSL) -> c.int ---
	SSL_get_error :: proc(ssl: ^SSL, ret: c.int) -> c.int ---
	SSL_read :: proc(ssl: ^SSL, buf: [^]byte, num: c.int) -> c.int ---
	SSL_write :: proc(ssl: ^SSL, buf: [^]byte, num: c.int) -> c.int ---
	SSL_free :: proc(ssl: ^SSL) ---
	SSL_CTX_free :: proc(ctx: ^SSL_CTX) ---
	ERR_print_errors_fp :: proc(fp: ^libc.FILE) ---
	SSL_ctrl :: proc(ssl: ^SSL, cmd: c.int, larg: c.long, parg: rawptr) -> c.long ---
	OpenSSL_version_num :: proc() -> c.ulong ---
}


SSL_set_tlsext_host_name :: proc(ssl: ^SSL, name: cstring) -> c.int {
	return c.int(SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, rawptr(name)))
}

ERR_print_errors :: proc {
	ERR_print_errors_fp,
	ERR_print_errors_stderr,
}

ERR_print_errors_stderr :: proc() {
	ERR_print_errors_fp(libc.stderr)
}

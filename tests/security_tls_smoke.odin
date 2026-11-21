package main

import http_client "../src/engine/util/odin-http/client"
import "core:fmt"
import "core:os"

main :: proc() {
	assert(len(os.args) == 3, "usage: security_tls_smoke URL accept|reject")
	response, err := http_client.get(os.args[1])
	if os.args[2] == "reject" {
		if err == nil {
			http_client.response_destroy(&response)
			panic("unexpectedly accepted untrusted TLS endpoint")
		}
	} else {
		assert(err == nil, fmt.tprintf("trusted TLS failed: %v", err))
		defer http_client.response_destroy(&response)
		body, allocated, body_err := http_client.response_body(&response, max_length = 1024)
		assert(body_err == nil)
		defer http_client.body_destroy(body, allocated)
		assert(body.(http_client.Body_Plain) == "TLS_OK")
	}
	fmt.println("SECURITY_TLS_SMOKE_PASSED")
}

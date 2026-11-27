#+build !linux
#+build !darwin
#+build !windows

package services

import "core:fmt"

Telemetry_LogCapture_Install :: proc() {}
Telemetry_LogCapture_Uninstall :: proc() {}

Telemetry_LogService_Output :: proc(tag, message: string) {
	if tag == "" {
		fmt.println(message)
	} else if tag == "ERROR" || tag == "WARN" {
		fmt.eprintf("[%s] %s\n", tag, message)
	} else {
		fmt.printf("[%s] %s\n", tag, message)
	}
}

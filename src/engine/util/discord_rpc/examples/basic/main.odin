package main

import rpc "../.."
import "core:fmt"
import "core:os"
import "core:time"

CLIENT_ID :: "123456789012345678"

main :: proc() {
	client: rpc.Client

	if err := rpc.connect(&client, CLIENT_ID); err != .None {
		fmt.eprintfln("Could not connect to Discord: %v (%s)", err, client.last_error.message)
		os.exit(1)
	}
	defer rpc.disconnect(&client)
	fmt.printfln("Connected as %s (%s)", client.user.username, client.user.id)

	buttons := [?]rpc.Button{{label = "Odin", url = "https://odin-lang.org"}}
	activity := rpc.Activity {
		details = "Writing Odin",
		state = "No C SDK needed",
		timestamps = {start = rpc.now_unix()},
		assets = {large_image = "odin_logo", large_text = "Odin"},
		buttons = buttons[:],
	}

	if err := rpc.set_activity(&client, activity); err != .None {
		fmt.eprintfln("set_activity failed: %v", err)
	}

	for i := 0; i < 60; i += 1 {
		err := rpc.update(&client, 1000)
		if err == .Connection_Closed || err == .Not_Connected {
			fmt.println("Lost Discord, retrying...")
			if rpc.connect(&client, CLIENT_ID) == .None {
				rpc.set_activity(&client, activity)
			} else {
				time.sleep(5 * time.Second)
			}
		}
		if client.last_error.code != 0 {
			fmt.eprintfln(
				"Discord error %d: %s",
				client.last_error.code,
				client.last_error.message,
			)
			client.last_error.code = 0
		}
	}

	rpc.clear_activity(&client)
	rpc.update(&client, 200)
}

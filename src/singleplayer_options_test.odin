#+build !js

package main

import "core:testing"

import target "engine/target"

@(test)
singleplayer_startup_options_test :: proc(t: ^testing.T) {
	expect := testing.expect

	options, ok := startup_options_for([]string{"game", "--singleplayer", "--map", "world.kine"})
	expect(t, ok, "--singleplayer with --map must be accepted")
	expect(t, options.singleplayer, "the singleplayer flag must be recorded")
	expect(t, options.mode == target.Mode.Singleplayer, "mode must be Singleplayer")
	expect(t, options.map_path == "world.kine", "the map path must be carried")
	expect(t, options.address == "", "a singleplayer session must have no address")


	expect(t, options.username == "Player", "a singleplayer session is played by a person")

	_, ok = startup_options_for(
		[]string{"game", "--singleplayer", "--map", "world.kine", "--address", "127.0.0.1"},
	)
	expect(t, !ok, "--singleplayer must reject --address")

	_, ok = startup_options_for(
		[]string{"game", "--singleplayer", "--map", "world.kine", "--port", "1234"},
	)
	expect(t, !ok, "--singleplayer must reject --port")

	_, ok = startup_options_for(
		[]string{"game", "--singleplayer", "--map", "world.kine", "--server"},
	)
	expect(t, !ok, "--singleplayer must reject --server")

	_, ok = startup_options_for([]string{"game", "--singleplayer"})
	expect(t, !ok, "--singleplayer must require --map")
}

@(test)
singleplayer_leaves_other_modes_alone_test :: proc(t: ^testing.T) {
	expect := testing.expect

	client, ok := startup_options_for(
		[]string {
			"game",
			"--client",
			"--playtest-host",
			"--address",
			"127.0.0.1",
			"--port",
			"1234",
		},
	)
	expect(t, ok, "a networked playtest client must still start")
	expect(t, client.singleplayer == false, "a networked client is not singleplayer")
	expect(t, client.mode == target.Mode.Client, "the client mode must be preserved")
	expect(t, client.address == "127.0.0.1", "the client address must be preserved")
	expect(t, client.playtest, "the playtest flag must be preserved")


	server, server_ok := startup_options_for([]string{"game", "--server"})
	expect(t, server_ok, "a server must still start")
	expect(t, server.singleplayer == false, "a server is not singleplayer")
	expect(t, server.mode == target.Mode.Server, "the server mode must be preserved")
	expect(t, server.address == "0.0.0.0", "a server keeps its default bind address")
}

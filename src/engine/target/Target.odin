package target

BUILD_TARGET_NAME :: #config(BUILD_TARGET, "editor")

#assert(
	BUILD_TARGET_NAME == "editor" ||
	BUILD_TARGET_NAME == "client" ||
	BUILD_TARGET_NAME == "player" ||
	BUILD_TARGET_NAME == "server",
	"BUILD_TARGET must be editor, client, or server",
)

Mode :: enum {
	Editor,
	Client,
	Server,
	Standalone,
}

when BUILD_TARGET_NAME == "server" {
	BUILD_DEFAULT :: Mode.Server
	BUILD_NAME :: "server"
} else when BUILD_TARGET_NAME == "client" || BUILD_TARGET_NAME == "player" {
	BUILD_DEFAULT :: Mode.Client
	BUILD_NAME :: "client"
} else {
	BUILD_DEFAULT :: Mode.Editor
	BUILD_NAME :: "editor"
}

// Compile-time build target (the mode a dedicated build defaults to).
// Runtime flags (--server/--client/--editor) override it per-process.
ACTIVE :: BUILD_DEFAULT
NAME :: BUILD_NAME

IS_EDITOR :: ACTIVE == Mode.Editor
IS_CLIENT :: ACTIVE == Mode.Client
IS_SERVER :: ACTIVE == Mode.Server

// Runtime mode selection. Set once at startup from --server/--client/--editor,
// defaulting to the build target so dedicated -define:BUILD_TARGET=server
// binaries still run as a server without flags.
current_mode := BUILD_DEFAULT

// playtest is set when the process was launched by PlaytestService to host a
// playtest server or client. It is tracked here rather than kept in the startup
// options so any part of the engine can ask whether it is inside a playtest, the
// same way it asks about the current mode.
playtest := false

set_mode :: proc(mode: Mode) {
	current_mode = mode
}

set_playtest :: proc(value: bool) {
	playtest = value
}

is_playtest :: proc() -> bool {
	return playtest
}

is_editor :: proc() -> bool {
	return current_mode == .Editor
}

is_client :: proc() -> bool {
	return current_mode == .Client
}

is_server :: proc() -> bool {
	return current_mode == .Server
}

name :: proc() -> string {
	switch current_mode {
	case .Server:
		return "server"
	case .Client:
		return "client"
	case .Editor:
		return "editor"
	case .Standalone:
		return "standalone"
	}
	return "editor"
}

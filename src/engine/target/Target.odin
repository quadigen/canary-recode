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
	Singleplayer,
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


ACTIVE :: BUILD_DEFAULT
NAME :: BUILD_NAME

IS_EDITOR :: ACTIVE == Mode.Editor
IS_CLIENT :: ACTIVE == Mode.Client
IS_SERVER :: ACTIVE == Mode.Server


current_mode := BUILD_DEFAULT


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
	case .Singleplayer:
		return "singleplayer"
	}
	return "editor"
}

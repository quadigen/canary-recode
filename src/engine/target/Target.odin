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
}

when BUILD_TARGET_NAME == "server" {
	ACTIVE :: Mode.Server
	NAME :: "server"
} else when BUILD_TARGET_NAME == "client" || BUILD_TARGET_NAME == "player" {
	ACTIVE :: Mode.Client
	NAME :: "client"
} else {
	ACTIVE :: Mode.Editor
	NAME :: "editor"
}

IS_EDITOR :: ACTIVE == Mode.Editor
IS_CLIENT :: ACTIVE == Mode.Client
IS_SERVER :: ACTIVE == Mode.Server

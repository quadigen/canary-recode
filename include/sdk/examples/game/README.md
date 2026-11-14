# Compiled games

A compiled game is a native shared library built against [kine_game.h](../../kine_game.h).
Any compiler that can produce the platform's native C ABI can implement the
entry point. Build the library for the same operating system and architecture as
Kinemium.

On Linux, from the engine repository root, build and run the example with:

```sh
cc -std=c11 -shared -fPIC -Iinclude/sdk include/sdk/examples/game/hello.c -o hello-game.so
./build/kinemium --game-library ./hello-game.so
```

The example creates a Part, moves it for two seconds, and requests shutdown.
Add `--headless` to run without a window or `--map scene.kine` to load a scene
before `start`. Use `--server` or `--client` to select a network role. The library
runs as native code in the engine process.

Export `kine_game_entry` and return a static lifecycle descriptor. In `start`,
retain the host API table for use from `update` and `stop`. The table supports
service lookup, instance creation, property reads and writes, method calls,
logging, and shutdown. Call it from the lifecycle thread. Check operation
results and copy borrowed strings before the callback returns. Instance handles
are valid while their objects are alive.

Pass the library explicitly when launching the game. Studio playtest and game
export currently use their existing workflows. KNE extensions have their own
entry point and ABI.

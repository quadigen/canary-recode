# justfile

set shell := ["powershell.exe", "-NoProfile", "-Command"]

git_commit := `git rev-parse --short HEAD`
git_branch := `git rev-parse --abbrev-ref HEAD`

# Release version. Bump when cutting a release; the `release` recipe stamps
# it over the "1.19.0-dev" defaults so released binaries stop offering updates
# to their own version.
version := "1.19.0"

default:
    @just --list

build:
    odin build src -out:build/kinemium.exe

debug:
    odin build src -debug -out:build/kinemium-debug.exe -extra-linker-flags:"/LTCG /IGNORE:4099"

release:
    odin build src -o:speed -out:build/kinemium.exe -define:BUILD_TARGET=editor -define:RUNTIME_VERSION_DISPLAY={{version}} -define:RUNTIME_GIT_ENABLED=true -define:RUNTIME_GIT_COMMIT={{git_commit}} -define:RUNTIME_GIT_BRANCH={{git_branch}}

wasm:
    & ./tools/build_wasm.ps1

wasm-serve:
    python -m http.server 8000 --directory build/web

android:
    & ./tools/build_android.ps1

run: build
    ./build/kinemium.exe

run-debug: debug
    ./build/kinemium-debug.exe

run-sandbox script="C:\\Users\\devco\\Documents\\Kinemium-Canary\\src\\sandboxed\\internals\\gui\\mainframe.luau": debug
    ./build/kinemium-debug.exe --script "{{script}}"

test:
    odin test src

check:
    odin check src

wire:
    @& ./tools/wire_engine.ps1
    @odin check src

wire-check:
    @& ./tools/wire_engine.ps1 -Check

editor:
    odin build src -define:BUILD_TARGET=editor -out:build/kinemium-editor.exe

client:
    odin build src -define:BUILD_TARGET=client -out:build/kinemium-client.exe

player: client

server:
    odin build src -define:BUILD_TARGET=server -out:build/kinemium-server.exe

release-templates:
    New-Item -ItemType Directory -Force rel | Out-Null
    copy build\kinemium-server.exe rel\kinemium-server-windows-x86_64.exe
    copy build\kinemium-client.exe rel\kinemium-client-windows-x86_64.exe

server-bake map address="0.0.0.0" port="1234":
    odin build src -define:BUILD_TARGET=server -define:KINE_MODE=server -define:KINE_ADDRESS={{address}} -define:KINE_PORT={{port}} -define:KINE_EMBED="$(Resolve-Path '{{map}}')" -out:build/kinemium-server.exe

client-bake address="" map="" port="1234":
    odin build src -define:BUILD_TARGET=client -define:KINE_MODE=client {{ if address != "" { "-define:KINE_ADDRESS=" + address + " " } else { "" } }}-define:KINE_PORT={{port}} {{ if map != "" { "-define:KINE_EMBED=\"$(Resolve-Path '" + map + "')\" " } else { "" } }}-out:build/kinemium-client.exe

run-editor:
    odin run src -define:BUILD_TARGET=editor

playtest map: editor
    ./build/kinemium-editor.exe "{{map}}"

run-client:
    odin run src -define:BUILD_TARGET=client

run-player: run-client

run-server:
    odin run src -define:BUILD_TARGET=server

fmt:
    odinfmt -w src

clean:
    if (Test-Path build) { Remove-Item -Recurse -Force build }
    New-Item -ItemType Directory -Force build | Out-Null

rebuild: clean build

deps:
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

deps-rebuild:
    if (Test-Path vendor/build) { Remove-Item -Recurse -Force vendor/build }
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

all: deps build

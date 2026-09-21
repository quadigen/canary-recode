# justfile

set shell := ["powershell.exe", "-NoProfile", "-Command"]

default:
    @just --list

build:
    odin build src -out:build/kinemium.exe

debug:
    odin build src -debug -out:build/kinemium-debug.exe -extra-linker-flags:"/LTCG /IGNORE:4099"

release:
    odin build src -o:speed -out:build/kinemium.exe

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

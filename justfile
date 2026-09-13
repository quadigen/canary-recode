# justfile

set shell := ["powershell.exe", "-NoProfile", "-Command"]

default:
    @just --list

# Build the engine
build:
    odin build src -out:build/kinemium.exe

# Build with debug info
debug:
    odin build src -debug -out:build/kinemium-debug.exe -extra-linker-flags:"/LTCG /IGNORE:4099"

# Build optimized release
release:
    odin build src -o:speed -out:build/kinemium.exe

# Build the full engine for Firefox with Luau, Jolt, CanvasKit, and Filament WebGL.
wasm:
    & ./tools/build_wasm.ps1

# Serve build/web on http://127.0.0.1:8000 after running `just wasm`.
wasm-serve:
    python -m http.server 8000 --directory build/web

# Build an ARM64 Android debug APK with SDL3, Vulkan, Skia, Filament, Jolt, Luau, and miniaudio.
android:
    & ./tools/build_android.ps1

# Run the engine
run: build
    ./build/kinemium.exe

# Run debug build
run-debug: debug
    ./build/kinemium-debug.exe

# Run an external Luau sandbox entry point with the debug engine
run-sandbox script="C:\\Users\\devco\\Documents\\Kinemium-Canary\\src\\sandboxed\\internals\\gui\\mainframe.luau": debug
    ./build/kinemium-debug.exe --script "{{script}}"

# Run tests
test:
    odin test src

# Check code without producing an executable
check:
    odin check src

# Discover new engine types and refresh their registries
wire:
    @& ./tools/wire_engine.ps1
    @odin check src

# Verify generated wiring without changing files
wire-check:
    @& ./tools/wire_engine.ps1 -Check

# Format all Odin code
fmt:
    odinfmt -w src

# Remove generated build files
clean:
    if (Test-Path build) { Remove-Item -Recurse -Force build }
    New-Item -ItemType Directory -Force build | Out-Null

# Rebuild from scratch
rebuild: clean build

# Build native C/C++ dependencies with CMake + Ninja
deps:
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

# Clean and rebuild dependencies
deps-rebuild:
    if (Test-Path vendor/build) { Remove-Item -Recurse -Force vendor/build }
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

# Build dependencies, then the engine
all: deps build

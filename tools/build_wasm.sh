#!/usr/bin/env bash
# Unix counterpart to build_wasm.ps1. All native archives target wasm32.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"

target="${1:-editor}"
address="${2:-}"
port="${3:-}"
case "$target" in
  editor) output="$repo/build/web"; page=index.html ;;
  client) output="$repo/build/web-client"; page=client.html ;;
  *) echo "Usage: $0 [editor|client] [address] [port]" >&2; exit 2 ;;
esac

sdk="${EMSDK:-$repo/.tools/emsdk}"
if ! command -v emcc >/dev/null || ! command -v emcmake >/dev/null; then
  if [[ -f "$sdk/emsdk_env.sh" && -x "$sdk/upstream/emscripten/emcc" ]]; then
    # EMSDK's environment script is not necessarily nounset-safe.
    set +u
    source "$sdk/emsdk_env.sh"
    set -u
  fi
fi
for tool in odin emcc em++ emcmake em-config embuilder cmake ninja npm python3; do
  if ! command -v "$tool" >/dev/null; then
    echo "Missing $tool. For Emscripten, run: just wasm-setup" >&2
    exit 1
  fi
done

odin_root="$(odin root)"
runtime="$odin_root/core/sys/wasm/js/odin.js"
if [[ ! -f "$runtime" ]]; then echo "Odin JS runtime not found: $runtime" >&2; exit 1; fi
native="$repo/build/web-native"
lib="$native/lib"
mkdir -p "$lib" "$output"
# Use cached native dependency source checkouts when present (not host binaries).
cmake_args=()
for dep in jolt vhacd recastnavigation; do
  path="$repo/vendor/build/_deps/$dep-src"
  if [[ -d "$path" ]]; then
    cmake_args+=("-DFETCHCONTENT_SOURCE_DIR_${dep^^}=$path")
  fi
done
emcmake cmake -S "$repo/cmake/web-native" -B "$native" -G Ninja -DCMAKE_BUILD_TYPE=Release "${cmake_args[@]}"
cmake --build "$native" --config Release --parallel "${KINE_WEB_JOBS:-4}" --target kine_luau JoltWrapper RecastWrapper

emcc -r -Wl,--whole-archive "$lib/libkine_luau.a" -Wl,--no-whole-archive \
  "$native/luau/libLuau.VM.a" "$native/luau/libLuau.Compiler.a" \
  "$native/luau/libLuau.Ast.a" "$native/luau/libLuau.Bytecode.a" \
  "$native/luau/libLuau.Common.a" -o "$lib/kine_luau_web.o"
emcc -r -Wl,--whole-archive "$lib/libJoltWrapper.a" -Wl,--no-whole-archive \
  "$lib/libJolt.a" -o "$lib/kine_jolt_web.o"
emcc -r -Wl,--whole-archive "$lib/libRecastWrapper.a" -Wl,--no-whole-archive \
  "$lib/libRecast.a" "$lib/libDetour.a" -o "$lib/kine_recast_web.o"
for source in luacode_link lualib_link lexer_link webview_link web_allocator; do
  name="kine_$source"
  [[ "$source" == web_allocator ]] && name=web_allocator
  emcc -c "$repo/cmake/web-native/$source.c" -o "$lib/$name.o"
done

# Build the exact JS-exception runtime variants used by the custom host.
version="$(emcc --version)"
if [[ ! "$version" =~ ([0-9]+)\.[0-9]+\.[0-9]+ ]]; then
  echo "Could not determine Emscripten version" >&2
  exit 1
fi
runtime_names=(libc++ libc++abi libc)
if (( BASH_REMATCH[1] >= 7 )); then
  runtime_names+=(libemcc libclang_rt.builtins)
else
  runtime_names+=(libcompiler_rt)
fi
embuilder build "${runtime_names[@]}"
cache_root="$(em-config CACHE)"
syslib="$cache_root/sysroot/lib/wasm32-emscripten"
for name in "${runtime_names[@]}"; do
  archive="$name.a"
  if [[ ! -f "$syslib/$archive" ]]; then
    echo "Missing Emscripten runtime archive: $syslib/$archive" >&2
    exit 1
  fi
  cp "$syslib/$archive" "$lib/$archive"
done
flags=(--allow-multiple-definition --export-table --strip-debug --export=__wasm_call_ctors)
for symbol in setThrew _emscripten_tempret_set _emscripten_tempret_get __cxa_increment_exception_refcount __cxa_decrement_exception_refcount __cxa_can_catch __cxa_get_exception_ptr emscripten_stack_get_current _emscripten_stack_restore; do
  flags+=("--export=$symbol")
  [[ "$symbol" == _emscripten_tempret_get ]] || flags+=("--undefined=$symbol")
done
for symbol in malloc free calloc realloc posix_memalign strcmp; do flags+=("--wrap=$symbol"); done
# Linker flags use relative paths to avoid splitting repository paths with spaces.
flags+=(build/web-native/lib/web_allocator.o)
for name in "${runtime_names[@]}"; do flags+=("build/web-native/lib/$name.a"); done
args=(build src -target:js_wasm32 -o:speed "-define:BUILD_TARGET=$target" "-out:$output/kinemium_engine.wasm" "-extra-linker-flags:${flags[*]}")
modules="${KINEMIUM_EDITOR_MODULES:-$repo/../kinemium-editor/internal}"
if [[ "$target" == editor && -d "$modules" ]]; then
  modules="$(cd "$modules" && pwd)"
  package="$repo/build/web-native/editor-modules.kemp"
  python3 "$repo/tools/pack_editor_modules.py" "$modules" "$package"
  args+=("-define:EDITOR_PACKAGE=$package")
elif [[ "$target" == editor ]]; then
  echo "Editor modules not found at $modules. Set KINEMIUM_EDITOR_MODULES or clone kinemium-editor next to this repository." >&2
  exit 1
fi
[[ -z "$address" ]] || args+=("-define:KINE_ADDRESS=$address")
[[ -z "$port" ]] || args+=("-define:KINE_PORT=$port")
odin "${args[@]}"

canvaskit="$repo/.cache/web-deps/node_modules/canvaskit-wasm/bin"
if [[ ! -f "$canvaskit/canvaskit.js" || ! -f "$canvaskit/canvaskit.wasm" ]]; then
  npm install --prefix "$repo/.cache/web-deps" --no-save --package-lock=false --ignore-scripts canvaskit-wasm@0.42.0
fi
babylon="$repo/.cache/babylon-web/node_modules/babylonjs"
if [[ ! -f "$babylon/babylon.js" ]] || ! node -e 'process.exit(require(process.argv[1]).version==="9.37.1"?0:1)' "$babylon/package.json"; then
  npm install --prefix "$repo/.cache/babylon-web" --no-save --package-lock=false --ignore-scripts babylonjs@9.37.1
fi
mkdir -p "$output/canvaskit" "$output/babylon" "$output/fonts"
cp "$repo/web/$page" "$output/index.html"
[[ "$page" == index.html ]] || cp "$repo/web/$page" "$output/$page"
cp "$repo/web/app.css" "$repo/web/app.js" "$repo/web/babylon_backend.js" "$output/"
cp "$runtime" "$output/odin.js"
cp "$canvaskit/canvaskit.js" "$canvaskit/canvaskit.wasm" "$output/canvaskit/"
cp "$babylon/babylon.js" "$output/babylon/"
for notice in license.md NOTICE.md; do
  [[ ! -f "$babylon/$notice" ]] || cp "$babylon/$notice" "$output/babylon/"
done
cp "$repo/src/engine/assets/fonts/Roboto-VariableFont_wdth_wght.ttf" "$output/fonts/Roboto.ttf"
python3 "$repo/tools/stage_web_assets.py" "$output"
echo "KINEMIUM_WASM_BUILD_PASSED $output/kinemium_engine.wasm"

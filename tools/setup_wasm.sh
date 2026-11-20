#!/usr/bin/env bash
# Install Emscripten into the repository-local SDK; no sudo required.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="${EMSDK:-$repo/.tools/emsdk}"
if [[ ! -x "$sdk/emsdk" ]]; then
  mkdir -p "$(dirname "$sdk")"
  git clone https://github.com/emscripten-core/emsdk.git "$sdk"
fi
cd "$sdk"
./emsdk install "${KINE_EMSDK_VERSION:-latest}"
./emsdk activate "${KINE_EMSDK_VERSION:-latest}"
echo "Emscripten installed. Run just wasm from the repository."

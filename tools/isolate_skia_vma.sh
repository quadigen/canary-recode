#!/usr/bin/env bash
set -euo pipefail

archive="${1:?pass the Skia static archive path}"
test -s "$archive"

for tool in nm objcopy ranlib; do
  command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 1; }
done

map_file="$(mktemp)"
isolated_archive="$(mktemp "${archive}.isolated.XXXXXX")"
trap 'rm -f "$map_file" "$isolated_archive"' EXIT

# Skia and Filament each compile a different version of Vulkan Memory Allocator.
# Both implementations export the same C API and C++ implementation symbols.
# Rename Skia's definitions and every reference to them within its archive so
# Filament's VulkanDriver cannot bind to Skia's incompatible allocator layout.
nm -A -g --defined-only "$archive" |
  awk 'index($0, "VulkanMemoryAllocatorWrapper") {
    symbol = $NF
    if (symbol ~ /^vma[A-Za-z0-9_]*$/ ||
        symbol ~ /Vma[A-Za-z0-9_]+/ ||
        symbol ~ /VMA[A-Za-z0-9_]+/) {
      if (!seen[symbol]++) print symbol, "kine_skia_" symbol
    }
  }' > "$map_file"

grep -q 'VmaAllocator' "$map_file" || {
  echo "Could not find Skia's VMA implementation in $archive" >&2
  exit 1
}

objcopy --redefine-syms="$map_file" "$archive" "$isolated_archive"
ranlib "$isolated_archive"
nm -g --defined-only "$isolated_archive" |
  awk '$NF ~ /^kine_skia_.*VmaAllocator/ { found = 1 } END { exit !found }' || {
  echo "Skia VMA symbol isolation failed" >&2
  exit 1
}

mv -f "$isolated_archive" "$archive"
echo "Isolated $(wc -l < "$map_file") Skia VMA symbols in $archive"

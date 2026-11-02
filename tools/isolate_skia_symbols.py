#!/usr/bin/env python3
"""Keep the prebuilt Skia shader compiler separate from Filament's copy."""

import argparse
import glob
from pathlib import Path
import shutil
import subprocess
import tempfile


def llvm_tool(name):
    found = shutil.which(name)
    if found:
        return found
    directories = ["C:/Program Files/LLVM/bin", ".tools/emsdk/upstream/bin"]
    for pattern in ("/usr/lib/llvm-*/bin", "/opt/homebrew/opt/llvm*/bin", "/usr/local/opt/llvm*/bin"):
        directories.extend(sorted(glob.glob(pattern), reverse=True))
    for directory in directories:
        for suffix in ("", ".exe"):
            candidate = Path(directory) / (name + suffix)
            if candidate.is_file():
                return str(candidate.resolve())
    raise RuntimeError(f"{name} is required to isolate the Skia prebuilt; install LLVM tools")


def isolate(root):
    root = root.resolve()
    marker = root / ".shader-symbols-v1"
    if marker.is_file():
        print("Skia shader compiler symbols are already isolated")
        return
    archives = sorted(root.glob("out/Release-*/*"))
    archives = [p for p in archives if p.suffix in (".a", ".lib")
                and p.stem.removeprefix("lib") in
                ("skia", "svg", "skshaper", "skunicode_core", "skunicode_icu")]
    if len(archives) != 5:
        raise RuntimeError("Expected the five Skia component archives")
    nm = llvm_tool("llvm-nm")
    objcopy = llvm_tool("llvm-objcopy")
    symbols = set()
    for archive in archives:
        output = subprocess.check_output([nm, "--extern-only", "--just-symbol-name", str(archive)], text=True)
        symbols.update(line.strip() for line in output.splitlines()
                       if "spirv_cross" in line and not line.endswith(":"))
    with tempfile.TemporaryDirectory(dir=root) as temporary:
        temporary = Path(temporary)
        mapping = temporary / "symbols.txt"
        mapping.write_text("".join(f"{name} kine_skia_{name}\n" for name in sorted(symbols)), encoding="utf-8")
        if symbols:
            # Stage every rewritten archive before replacing any package file.
            for archive in archives:
                subprocess.run([objcopy, f"--redefine-syms={mapping}", str(archive),
                                str(temporary / archive.name)], check=True)
            for archive in archives:
                (temporary / archive.name).replace(archive)
    marker.write_text(f"Isolated {len(symbols)} SPIRV-Cross symbols\n", encoding="utf-8")
    print(marker.read_text(encoding="utf-8").strip())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    isolate(parser.parse_args().root)

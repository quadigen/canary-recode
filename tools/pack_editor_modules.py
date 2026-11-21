#!/usr/bin/env python3
"""Pack kinemium-editor's internal Luau tree into the KEMP browser module format.

Format: b"KEMP", little-endian u32 count, then (name, source) pairs,
each a little-endian u32 byte length followed by that many bytes.
Module names are relative to the internal root and omit .luau.
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

MAX_MODULES = 100_000
U32_MAX = (1 << 32) - 1


def pack_modules(source_dir: Path, output: Path) -> int:
    if not source_dir.is_dir():
        raise ValueError(f"Editor module directory does not exist: {source_dir}")

    files = sorted(
        (p for p in source_dir.rglob("*.luau") if p.is_file() and not p.is_symlink()),
        key=lambda p: p.relative_to(source_dir).as_posix(),
    )
    if not files or len(files) > MAX_MODULES:
        raise ValueError(f"Expected 1-{MAX_MODULES} Luau modules, found {len(files)}")

    names: set[str] = set()
    entries: list[tuple[bytes, bytes]] = []
    for file in files:
        relative = file.relative_to(source_dir).as_posix()
        name = relative[:-len(".luau")]
        if (
            not name
            or ".." in name
            or "\\" in name
            or '"' in name
            or name in names
        ):
            raise ValueError(f"Invalid or duplicate editor module name: {name!r}")
        names.add(name)
        name_bytes = name.encode("utf-8")
        source_bytes = file.read_bytes()
        if len(name_bytes) > U32_MAX or len(source_bytes) > U32_MAX:
            raise ValueError(f"Editor module too large: {file}")
        entries.append((name_bytes, source_bytes))

    if "editor_ui" not in names:
        raise ValueError(f"Missing editor_ui.luau entrypoint in {source_dir}")

    # Validate the full input tree before producing an output file.
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as dest:
        dest.write(b"KEMP")
        dest.write(struct.pack("<I", len(entries)))
        for name, source in entries:
            dest.write(struct.pack("<I", len(name)))
            dest.write(name)
            dest.write(struct.pack("<I", len(source)))
            dest.write(source)
    return len(entries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("internal_dir", type=Path)
    parser.add_argument("package_path", type=Path)
    args = parser.parse_args()
    try:
        count = pack_modules(args.internal_dir, args.package_path)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Cannot package editor modules: {exc}\n")
    print(f"Packed {count} editor modules into {args.package_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

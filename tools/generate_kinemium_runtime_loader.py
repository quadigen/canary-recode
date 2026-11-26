#!/usr/bin/env python3
"""Regenerate the type-safe Kinemium runtime symbol list from the C ABI header.

This script intentionally does not re-parse C structs, typedefs, or callback
signatures; it extracts only top-level KINEMIUM_API prototypes. Failure to
account for every prototype is an error, not an incomplete generated loader.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
HEADER = ROOT / "include/kinemium.h"
GENERATED = ROOT / "include/kinemium_runtime_symbols.h"
DECL = re.compile(
    r"KINEMIUM_API\s+([A-Za-z_]\w*(?:\s*\*+\s*)?)\s*"
    r"(Kinemium_\w+)\s*\((.*?)\)\s*;", re.S,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Exit nonzero if generated header is stale")
    options = parser.parse_args()
    original = HEADER.read_text(encoding="utf-8")
    prototypes = DECL.findall(original)
    exported_count = len(re.findall(r"^KINEMIUM_API\s+[A-Za-z_]", original, re.M))
    if not prototypes or exported_count != len(prototypes):
        raise ValueError(f"SDK header has {exported_count} declarations; parser matched {len(prototypes)}")
    names = [name for _, name, _ in prototypes]
    if len(set(names)) != len(names):
        raise ValueError("Duplicate exported function declaration")
    output = [
        "#ifndef KINEMIUM_RUNTIME_SYMBOLS_H",
        "#define KINEMIUM_RUNTIME_SYMBOLS_H",
        "",
        "#define KINEMIUM_RUNTIME_SYMBOLS(X) \\",
    ]
    for index, (result, name, args) in enumerate(prototypes):
        args = re.sub(r"\s+", " ", args.strip())
        result = re.sub(r"\s+", " ", result.strip())
        suffix = " \\" if index + 1 != len(prototypes) else ""
        output.append(f"    X({result}, {name[len('Kinemium_'):]}, ({args})){suffix}")
    output += [
        "",
        f"#define KINEMIUM_RUNTIME_SYMBOL_COUNT {len(prototypes)}u",
        "",
        "#endif",
        "",
    ]
    rendered = "\n".join(output)
    if options.check:
        if not GENERATED.exists() or GENERATED.read_text(encoding="utf-8") != rendered:
            print(f"Generated file is stale: {GENERATED}", file=sys.stderr)
            return 1
        print(f"Verified runtime loader symbol declarations: {len(prototypes)}")
    else:
        GENERATED.write_text(rendered, encoding="utf-8")
        print(f"Generated {GENERATED}: {len(prototypes)} function signatures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

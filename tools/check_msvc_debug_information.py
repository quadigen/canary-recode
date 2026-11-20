"""Reject native compile commands that would write shared MSVC PDBs."""
import json
import re
import sys
from pathlib import Path

DEBUG_FORMAT = re.compile(r'(?<!\S)"?[-/]Z([iI7])"?(?=\s|$)')


def shared_pdb_commands(commands):
    for entry in commands:
        if "arguments" in entry:
            formats = [
                match.group(1)
                for arg in entry["arguments"]
                if (match := DEBUG_FORMAT.fullmatch(arg))
            ]
        else:
            formats = DEBUG_FORMAT.findall(entry["command"])
        # MSVC uses the last debug-format option if several are supplied.
        if formats and formats[-1] in ("i", "I"):
            yield entry["file"]


def main():
    commands = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
    failures = list(shared_pdb_commands(commands))
    if failures:
        print("Shared compiler PDB (/Zi or /ZI) still enabled:", file=sys.stderr)
        for failure in failures[:20]:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"Validated {len(commands)} compile commands: no shared compiler PDBs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

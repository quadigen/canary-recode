"""Reject native compile commands that would write shared MSVC PDBs."""
import json
import re
import sys
import subprocess
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


def compiler_cache_commands(commands):
    cache = re.compile(r'(?:^|[\\/"\s])s?ccache(?:\.exe)?(?=["\s]|$)', re.IGNORECASE)
    return [command for command in commands if cache.search(command)]


def main():
    database = Path(sys.argv[1])
    commands = json.loads(database.read_text(encoding="utf-8-sig"))
    failures = list(shared_pdb_commands(commands))
    if failures:
        print("Shared compiler PDB (/Zi or /ZI) still enabled:", file=sys.stderr)
        for failure in failures[:20]:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"Validated {len(commands)} compile commands: no shared compiler PDBs.")
    if "--no-compiler-cache" in sys.argv[2:]:
        # compile_commands.json excludes launcher prefixes. Check the actual
        # commands Ninja will execute, including upstream launcher overrides.
        ninja = subprocess.run(
            ["ninja", "-C", str(database.parent), "-t", "commands"],
            check=True, capture_output=True, text=True, errors="replace",
        )
        cached = compiler_cache_commands(ninja.stdout.splitlines())
        if cached:
            print("Unexpected Windows compiler cache launcher:", file=sys.stderr)
            for command in cached[:5]:
                print(command, file=sys.stderr)
            return 1
        print("Validated Ninja commands: no ccache or sccache launchers.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

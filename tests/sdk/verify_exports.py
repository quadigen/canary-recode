import pathlib
import re
import subprocess
import sys

header = pathlib.Path(sys.argv[1]).read_text()
library = pathlib.Path(sys.argv[2])
declared = set(re.findall(r"\b(Kinemium_[A-Za-z0-9_]+)\s*\(", header))
if not declared:
    raise SystemExit("No Kinemium API declarations found")

if sys.platform == "darwin":
    command = ["nm", "-gU", str(library)]
else:
    command = ["nm", "-D", "--defined-only", str(library)]

symbols = subprocess.check_output(command, text=True)
exported = set()
for line in symbols.splitlines():
    name = line.split()[-1] if line.split() else ""
    if name.startswith("_Kinemium_"):
        name = name[1:]
    if name.startswith("Kinemium_"):
        exported.add(name)

missing = declared - exported
if missing:
    raise SystemExit("Missing exported symbols: " + ", ".join(sorted(missing)))
print(f"PASS SDK export audit: {len(declared)} declarations exported")

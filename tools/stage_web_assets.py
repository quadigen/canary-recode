"""Stage on-demand web assets without embedding them in the WASM binary."""
import json
import re
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]).resolve()
assets = root / "src/engine/assets"
font_dest = out / "fonts"
font_dest.mkdir(parents=True, exist_ok=True)
fonts = assets / "fonts"
for path in fonts.iterdir():
    if path.is_file() and path.suffix.lower() in (".ttf", ".otf", ".woff", ".woff2"):
        shutil.copy2(path, font_dest / path.name)
# Match the actual enum values used by the bridge.
enum_text = re.search(r"(?m)^Material :: enum \{([^}]*)\}", (root / "src/engine/enum/enum.odin").read_text()).group(1)
ids = dict(re.findall(r"(\w+)\s*=\s*(\d+)", enum_text))
mapping = re.findall(r'case \.(\w+):\s*return #load_directory\("../assets/materials/compressed/([^"]+)"\)', (root / "src/engine/material/Builtin.generated.odin").read_text())
manifest = {}
for name, folder in mapping:
    source = assets / "materials/compressed" / folder
    files = {}
    dest = out / "materials" / folder
    for channel in ("albedo", "normal", "orm"):
        for extension in ("png", "jpg", "jpeg"):
            path = source / f"{channel}.{extension}"
            if path.is_file():
                dest.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, dest / path.name)
                files[channel] = f"materials/{folder}/{path.name}"
                break
    if files.get("albedo"):
        manifest[ids[name]] = files
(out / "material-manifest.json").write_text(json.dumps(manifest,separators=(",", ":")))

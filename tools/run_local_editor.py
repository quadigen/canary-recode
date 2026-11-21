"""Launch an already built engine with a local editor module directory."""
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
if not (root / "editor_ui.luau").is_file():
    sys.exit(f"Editor directory has no editor_ui.luau: {root}")
env = dict(os.environ, KINEMIUM_EDITOR_DIR=str(root))
sys.exit(subprocess.call([sys.argv[2], *sys.argv[3:]], env=env))

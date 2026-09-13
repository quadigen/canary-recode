from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".cache" / "pydeps"))

from selenium import webdriver
from selenium.webdriver.firefox.options import Options


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8765/")
    parser.add_argument("--output", default=str(ROOT / "build" / "wasm-firefox-real.png"))
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    options = Options()
    options.binary_location = r"C:\Program Files\Mozilla Firefox\firefox.exe"
    options.add_argument("-headless")
    driver = webdriver.Firefox(options=options)
    try:
        driver.set_window_size(1440, 900)
        driver.get(args.url)
        deadline = time.monotonic() + args.timeout
        state = {}
        while time.monotonic() < deadline:
            state = driver.execute_script(
                "return {ready:document.documentElement.dataset.engineReady||'',"
                "error:document.documentElement.dataset.engineError||'',"
                "status:document.getElementById('startup-status')?.textContent||'',"
                "runtime:document.getElementById('runtime-value')?.textContent||'',"
                "stack:window.__kinemiumError||'',"
                "logs:(window.__kinemiumLogs||[]).join(''),"
                "stats:window.__kinemiumStats||{}};"
            )
            if state["error"]:
                break
            if state["ready"] and state.get("stats", {}).get("frames", 0) >= 3:
                break
            time.sleep(0.25)
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        driver.save_screenshot(args.output)
        print(json.dumps(state, sort_keys=True))
        print(f"FIREFOX_SCREENSHOT={Path(args.output).resolve()}")
        if state.get("error") or not state.get("ready") or state.get("stats", {}).get("frames", 0) < 3:
            print("FIREFOX_WASM_SMOKE_FAILED")
            return 1
        print("FIREFOX_WASM_SMOKE_PASSED")
        return 0
    finally:
        driver.quit()


if __name__ == "__main__":
    raise SystemExit(main())

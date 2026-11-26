from __future__ import annotations

import argparse
import datetime
import json
import os
import platform
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESETS = {
    "light-720p": (1280, 720, 200, 0, 0),
    "standard-720p": (1280, 720, 800, 1, 1),
    "standard-1080p": (1920, 1080, 800, 1, 1),
    "dense-1080p": (1920, 1080, 2400, 1, 1),
    "dense-1440p": (2560, 1440, 2400, 1, 1),
}
PATTERN = re.compile(r"items=(\d+) mean=([\d.]+) ms \(([\d.]+) FPS\) p50=([\d.]+) ms p95=([\d.]+) ms p99=([\d.]+) ms")


def output(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=6)
        return result.stdout.strip() if result.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def hardware():
    cpu = platform.processor()
    if Path("/proc/cpuinfo").exists():
        for line in Path("/proc/cpuinfo").read_text(errors="replace").splitlines():
            if line.startswith("model name"):
                cpu = line.split(":", 1)[1].strip()
                break
    gpu = output(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"])
    if not gpu:
        gpu = next((line for line in output(["lspci"]).splitlines()
                    if "VGA compatible controller" in line or "3D controller" in line), "Unknown")
    return {"cpu": cpu, "gpu": gpu.splitlines()[0], "os": platform.platform(),
            "hostname": platform.node(), "cores": os.cpu_count()}


def build(binary):
    binary.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["odin", "build", "tests/tmp_3d_bench.odin", "-file", "-o:speed", f"-out:{binary}"]
    if platform.system() == "Linux":
        lib = ROOT / "vendor/build/lib"
        cmd.append(f"-extra-linker-flags:-L{lib} -Wl,-rpath,{lib}")
    subprocess.run(cmd, cwd=ROOT, check=True)


def run(binary, name, frames, seconds):
    width, height, parts, shadows, post = PRESETS[name]
    env = os.environ.copy()
    env.update({"BENCH_WIDTH": str(width), "BENCH_HEIGHT": str(height),
                "BENCH_PARTS": str(parts), "BENCH_FRAMES": str(frames),
                "BENCH_SHADOWS": str(shadows), "BENCH_POST_PROCESS": str(post),
                "BENCH_ANIMATE": "1"})
    row = {"name": name, "width": width, "height": height, "parts": parts,
           "shadows": bool(shadows), "post_processing": bool(post), "status": "failed"}
    try:
        result = subprocess.run([str(binary)], cwd=ROOT, env=env,
                                capture_output=True, text=True, timeout=seconds)
        log = result.stdout + "\n" + result.stderr
        match = PATTERN.search(log)
        if result.returncode == 0 and match:
            count, mean, fps, p50, p95, p99 = match.groups()
            row.update(status="ok", draw_items=int(count), mean_ms=float(mean),
                       fps=float(fps), p50_ms=float(p50), p95_ms=float(p95),
                       p99_ms=float(p99))
        else:
            row["error"] = f"exit={result.returncode}: {log[-800:]}"
    except subprocess.TimeoutExpired:
        row.update(status="timeout", error="GPU presentation or runtime exceeded timeout")
    return row


def main():
    parser = argparse.ArgumentParser(description="Repeatable Kinemium Vulkan rendering test")
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--binary", type=Path, default=ROOT / "build/kinemium-hardware-bench")
    parser.add_argument("--presets", nargs="+", choices=PRESETS, default=list(PRESETS))
    parser.add_argument("--frames", type=int, default=180)
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--output", type=Path, default=ROOT / "benchmarks/hardware-latest.json")
    args = parser.parse_args()
    binary = args.binary.expanduser().resolve()
    if args.build:
        build(binary)
    if not binary.is_file():
        parser.error(f"Binary does not exist: {binary}. Run with --build.")
    if args.frames <= 0 or args.timeout <= 0:
        parser.error("Frames and timeout must be positive")
    data = {"date": datetime.datetime.now().astimezone().isoformat(),
            "revision": output(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"]),
            "hardware": hardware(), "runs": []}
    for name in args.presets:
        print(f"Running {name}", flush=True)
        row = run(binary, name, args.frames, args.timeout)
        data["runs"].append(row)
        print(f"  {row['status']}: {row.get('fps', 'n/a')} FPS", flush=True)
        if row["status"] == "timeout":
            break
    target = args.output.expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, indent=2) + "\n")
    print(f"Saved {target}")


if __name__ == "__main__":
    main()

import argparse
import collections
import json
import math
from pathlib import Path
import re
import statistics

MARKER = re.compile(r"\bKINE_FILAMENT_PASS frame=(\d+) ns=(\d+) name=(.+)$")


def summarize(log, source=None):
    passes = collections.defaultdict(list)
    frames = collections.defaultdict(set)
    for line in log.splitlines():
        match = MARKER.search(line)
        if not match:
            continue
        prefix = line[:match.start()].strip()
        origin = "client" if prefix == "[Playtest client]" else "server" if prefix == "[Playtest server]" else "editor" if not prefix else "unknown"
        if source is not None and origin != source:
            continue
        frame, elapsed, name = match.groups()
        passes[name].append(int(elapsed) / 1_000_000)
        frames[name].add(int(frame))
    rows = []
    for name, samples in passes.items():
        samples.sort()
        rows.append({"pass": name, "samples": len(samples), "distinct_frame_ids": len(frames[name]),
                     "mean_ms": statistics.mean(samples), "p95_ms": samples[math.ceil(.95 * len(samples)) - 1],
                     "max_ms": samples[-1]})
    return sorted(rows, key=lambda row: row["mean_ms"], reverse=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--source", choices=("editor", "client", "server", "unknown"))
    args = parser.parse_args()
    rows = summarize(args.log.read_text(errors="replace"), args.source)
    if not rows:
        parser.exit(1, "No custom Filament pass timing samples found\n")
    print(json.dumps(rows, indent=2))


if __name__ == "__main__":
    main()

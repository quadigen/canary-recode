import argparse
from pathlib import Path
import struct
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--shader-dir", required=True, type=Path)
    parser.add_argument("--include-dir", required=True, type=Path)
    parser.add_argument("--compiler", default="glslangValidator")
    parser.add_argument("--validator", default="spirv-val")
    args = parser.parse_args()
    data = []
    with tempfile.TemporaryDirectory(prefix="kine-cloud-spv-") as directory:
        for name in ("shape", "detail", "curl"):
            source = args.shader_dir / ("cloud_noise_" + name + ".comp")
            output = Path(directory) / (name + ".spv")
            subprocess.run([
                args.compiler, "-V", "--target-env", "vulkan1.1",
                "-I" + str(args.include_dir), "-o", str(output), str(source)
            ], check=True, capture_output=True)
            subprocess.run([
                args.validator, "--target-env", "vulkan1.1", str(output)
            ], check=True, capture_output=True)
            contents = output.read_bytes()
            if not contents or len(contents) % 4 or len(contents) > 4 * 1024 * 1024:
                raise ValueError("Invalid SPIR-V size: " + name)
            words = struct.unpack("<" + "I" * (len(contents) // 4), contents)
            lines = []
            for i in range(0, len(words), 8):
                lines.append("    " + ", ".join(f"0x{word:08x}u" for word in words[i:i + 8]) + ",")
            data.append("static constexpr uint32_t kine_cloud_" + name +
                        "_spirv[] = {\n" + "\n".join(lines) + "\n};")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    content = "#pragma once\n#include <cstdint>\n\n" + "\n\n".join(data) + "\n"
    if not args.output.is_file() or args.output.read_text() != content:
        args.output.write_text(content)


if __name__ == "__main__":
    main()

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from build import ROOT


def compile_hlsl(source, output, *, dxc=None, entry="main", profile="cs_6_0", includes=(), defines=()):
    source = Path(source).resolve()
    output = Path(output).resolve()
    if not source.is_file():
        raise FileNotFoundError(source)
    bundled = ROOT / "vendor/Ray/third-party/dxc/linux/dxc"
    executable = dxc or shutil.which("dxc") or bundled
    executable = Path(executable).resolve()
    if not executable.is_file():
        raise FileNotFoundError(f"DXC not found: {executable}")
    output.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    if (executable.parent / "libdxcompiler.so").is_file():
        env["LD_LIBRARY_PATH"] = os.pathsep.join(filter(None, (str(executable.parent),
                env.get("LD_LIBRARY_PATH"))))
    with tempfile.TemporaryDirectory(prefix="kine-dxc-", dir=output.parent) as directory:
        work = Path(directory)
        compiler = executable
        if not os.access(compiler, os.X_OK):
            compiler = work / "dxc"
            shutil.copy2(executable, compiler)
            compiler.chmod(compiler.stat().st_mode | 0o100)
        spirv = work / "shader.spv"
        subprocess.run([str(compiler), "-spirv", "-fspv-target-env=vulkan1.1",
                        "-T", profile, "-E", entry, "-Fo", str(spirv),
                        *[flag for include in includes for flag in ("-I", str(Path(include).resolve()))],
                        *["-D" + define for define in defines], str(source)],
                       env=env, check=True)
        subprocess.run(["spirv-val", "--target-env", "vulkan1.1", str(spirv)], check=True)
        spirv.replace(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--dxc", type=Path)
    parser.add_argument("--entry", default="main")
    parser.add_argument("--profile", default="cs_6_0")
    parser.add_argument("-I", action="append", default=[])
    parser.add_argument("-D", action="append", default=[])
    args = parser.parse_args()
    compile_hlsl(args.source, args.output, dxc=args.dxc, entry=args.entry,
                 profile=args.profile, includes=args.I, defines=args.D)
    print(f"HLSL_SPIRV_VALIDATED {args.output}")


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

VERSION = "18.1.8"
RELEASE = f"https://github.com/llvm/llvm-project/releases/download/llvmorg-{VERSION}"
RAW = f"https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-{VERSION}"
ASSETS = {
    "libcxxabi": "256c30d724eeb72713bc08ae1692f53aaf4ebe8a1d662c92bf59e69d6c53dce9",
    "libcxx": "bdecf90be0072bc720fd5c9c8ab061cdb197edd0c8ad3e170dc3e6bfaa49f388",
    "cmake": "59badef592dd34893cd319d42b323aaa990b452d05c7180ff20f23ab1b41e837",
    "runtimes": "9997c2e91e5438e2963306ba5019d85b5384b467535632738d8670ced8f07cb3",
}
MODULES = {
    "llvm/cmake/modules/GetHostTriple.cmake": "05a0861f9b37db628698eabcc20231ec1268d491b3ebdcfe2668f837fe57d08e",
    "llvm/cmake/config.guess": "3088fa29112ac4e7e4fb25d3afa195c22952054d4beff4926d6e065212c6f12a",
}


def run(*command: str, directory: Path | None = None) -> str:
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(
            f"{' '.join(command)} failed ({result.returncode}):\n"
            + "\n".join((result.stdout + "\n" + result.stderr).splitlines()[-80:])
        )
    return result.stdout


def download(url: str, path: Path, sha256: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    run("curl", "--fail", "--location", "--retry", "3", "--silent", "--show-error", url, "--output", str(path))
    if hashlib.sha256(path.read_bytes()).hexdigest() != sha256:
        raise RuntimeError(f"SHA-256 mismatch for {url}")


def require_gcc_unwinder(path: Path) -> None:
    dynamic = run("readelf", "-d", str(path))
    if "[libunwind.so.1]" in dynamic or "[libunwind.so.8]" in dynamic:
        raise RuntimeError(f"Unexpected LLVM or GNU libunwind dependency in {path}")
    if "[libgcc_s.so.1]" not in dynamic:
        raise RuntimeError(f"Missing GCC unwinder dependency in {path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)

    if os.uname().sysname != "Linux":
        raise RuntimeError("The custom C++ runtime is only built for Linux")

    with tempfile.TemporaryDirectory(prefix="kinemium-cxx-runtime-") as temp:
        root = Path(temp)
        for name, expected_hash in ASSETS.items():
            archive = root / f"{name}-{VERSION}.src.tar.xz"
            download(f"{RELEASE}/{archive.name}", archive, expected_hash)
            run("tar", "-xf", str(archive), "-C", str(root))
            (root / name).symlink_to(f"{name}-{VERSION}.src", target_is_directory=True)

        for name, expected_hash in MODULES.items():
            path = root / name
            download(f"{RAW}/{name}", path, expected_hash)
            if path.name == "config.guess":
                path.chmod(0o755)

        llvm_config = shutil.which("llvm-config") or shutil.which("llvm-config-18")
        if llvm_config is None:
            raise RuntimeError("LLVM development tools are required (llvm-config or llvm-config-18)")
        llvm_cmake = run(llvm_config, "--cmakedir").strip()
        if not Path(llvm_cmake).is_dir():
            raise RuntimeError(f"LLVM CMake modules were not found: {llvm_cmake}")
        configure = [
            "cmake", "-S", str(root / "runtimes"), "-B", str(root / "build"),
            "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_C_COMPILER=clang", "-DCMAKE_CXX_COMPILER=clang++",
            f"-DCMAKE_MODULE_PATH={llvm_cmake}",
            "-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi",
            "-DLIBCXXABI_USE_LLVM_UNWINDER=OFF",
            "-DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF",
            "-DLIBCXX_ENABLE_STATIC=OFF", "-DLIBCXXABI_ENABLE_STATIC=OFF",
            "-DLIBCXXABI_ENABLE_ASSERTIONS=OFF", "-DLIBCXX_ENABLE_ASSERTIONS=OFF",
            "-DLLVM_INCLUDE_TESTS=OFF", "-DLIBCXX_INCLUDE_TESTS=OFF",
            "-DLIBCXXABI_INCLUDE_TESTS=OFF", "-DLIBCXX_INCLUDE_BENCHMARKS=OFF",
        ]
        run(*configure)
        run("cmake", "--build", str(root / "build"), "--target", "cxx_shared", "cxxabi_shared", "--parallel", "4")

        for library in ("libc++.so", "libc++abi.so"):
            built = root / "build" / "lib" / (library + ".1.0")
            if not built.is_file():
                raise RuntimeError(f"C++ runtime not built: {built}")
            require_gcc_unwinder(built)
            shipped = output / (library + ".1")
            shutil.copy2(built, shipped)
            linker_name = output / library
            linker_name.unlink(missing_ok=True)
            linker_name.symlink_to(shipped.name)
            print(f"Built {shipped.name} using GCC's unwinder")


if __name__ == "__main__":
    main()

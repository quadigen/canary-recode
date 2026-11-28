from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

LINUX_BUNDLED_PREFIXES = (
    "libprotobuf.so", "libabsl_", "libutf8_", "libcrypto.so",
    "libssl.so", "libsodium.so", "libzstd.so", "libbrotli",
    "libcares.so", "libidn2.so", "libnghttp2.so", "libatomic.so",
)


def run(*args: str, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(args, capture_output=True, text=True, env=env)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args)} failed: {result.stderr or result.stdout}")
    return result.stdout


def materialize_symlinks(folder: Path) -> None:
    for path in sorted(folder.iterdir()):
        if path.is_symlink():
            target = path.resolve(strict=True)
            if not target.is_file():
                raise RuntimeError(f"invalid runtime library: {path}")
            data = target.read_bytes()
            path.unlink()
            path.write_bytes(data)


def is_elf(path: Path) -> bool:
    with path.open("rb") as stream:
        return stream.read(4) == b"\x7fELF"


def linux_needed(path: Path) -> set[str]:
    output = run("readelf", "-d", str(path))
    return set(re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", output))


def linux_dependencies(path: Path, folder: Path, discover: bool = True) -> list[tuple[str, Path]]:
    env = os.environ.copy()
    if discover:
        env["LD_LIBRARY_PATH"] = str(folder) + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    else:
        env.pop("LD_LIBRARY_PATH", None)
    output = run("ldd", str(path), env=env)
    result = []
    for line in output.splitlines():
        match = re.match(r"\s*(\S+)\s+=>\s+(\S+)", line)
        if match is None:
            continue
        name, location = match.groups()
        if location == "not":
            raise RuntimeError(f"{path.name}: missing dependency {name}")
        if not location.startswith("/"):
            raise RuntimeError(f"{path.name}: unresolved dependency {name}: {location}")
        result.append((name, Path(location)))
    return result


def stage_linux(folder: Path) -> None:
    files = [p for p in folder.iterdir() if p.is_file() and is_elf(p)]
    if not files:
        raise RuntimeError(f"no ELF binaries in {folder}")
    queued = files[:]
    visited: set[Path] = set()
    while queued:
        binary = queued.pop(0)
        if binary in visited:
            continue
        visited.add(binary)
        needed = linux_needed(binary)
        for name, source in linux_dependencies(binary, folder):
            if name not in needed or not name.startswith(LINUX_BUNDLED_PREFIXES):
                continue
            target = folder / name
            if not target.exists():
                shutil.copy2(source, target)
                queued.append(target)
                print(f"Staged Linux dependency {name}")
            elif target not in visited:
                queued.append(target)
    for binary in sorted(folder.iterdir()):
        if not binary.is_file() or not binary.name.startswith("lib") or not is_elf(binary):
            continue
        existing = run("patchelf", "--print-rpath", str(binary)).strip()
        paths = ["$ORIGIN"] + [item for item in existing.split(":") if item and item != "$ORIGIN"]
        run("patchelf", "--set-rpath", ":".join(paths), str(binary))
    for binary in sorted(folder.iterdir()):
        if not binary.is_file() or not is_elf(binary):
            continue
        needed = linux_needed(binary)
        for name, resolved in linux_dependencies(binary, folder, discover=False):
            if name in needed and (name.startswith(LINUX_BUNDLED_PREFIXES) or (folder / name).exists()):
                if resolved.resolve() != (folder / name).resolve():
                    raise RuntimeError(f"{binary.name}: {name} loaded outside artifact: {resolved}")
    print(f"Linux runtime closure verified in {folder}")


def mac_dependencies(path: Path) -> list[str]:
    output = run("otool", "-L", str(path))
    dependencies: list[str] = []
    skip_install_name = path.name.endswith(".dylib")
    for line in output.splitlines():
        if not line[:1].isspace():
            skip_install_name = path.name.endswith(".dylib")
            continue
        match = re.match(r"\s+(.+?) \((?:compatibility|current) version ", line)
        if match is None:
            continue
        if skip_install_name:
            skip_install_name = False
            continue
        dependency = match.group(1)
        if dependency not in dependencies:
            dependencies.append(dependency)
    return dependencies


def system_macos_dependency(value: str) -> bool:
    return value.startswith(("/usr/lib/", "/System/Library/"))


def source_macos_dependency(dependency: str, folder: Path, search: list[Path]) -> Path:
    name = Path(dependency).name
    if not name.endswith(".dylib"):
        raise RuntimeError(f"unsupported non-system macOS dependency {dependency}")
    if dependency.startswith("/") and Path(dependency).is_file():
        return Path(dependency)
    candidates = [folder / name]
    candidates += [directory / name for directory in search]
    for prefix in (Path("/opt/homebrew"), Path("/usr/local")):
        candidates += [
            prefix / "lib" / name,
            *prefix.glob("opt/*/lib/" + name),
            *prefix.glob("Cellar/*/*/lib/" + name),
        ]
    for path in candidates:
        if path.is_file():
            return path
    raise RuntimeError(f"could not resolve macOS runtime library {dependency}")


def stage_macos(folder: Path, search: list[Path]) -> None:
    binaries = [p for p in folder.iterdir()
                if p.is_file() and (p.name.startswith("kinemium") or p.name.endswith(".dylib"))]
    if not binaries:
        raise RuntimeError(f"no macOS binaries in {folder}")
    queued = binaries[:]
    visited: set[Path] = set()
    original_deps: dict[Path, list[str]] = {}
    while queued:
        binary = queued.pop(0)
        if binary in visited:
            continue
        visited.add(binary)
        dependencies = mac_dependencies(binary)
        original_deps[binary] = dependencies
        for dependency in dependencies:
            if system_macos_dependency(dependency):
                continue
            source = source_macos_dependency(dependency, folder, search)
            target = folder / source.name
            if not target.exists():
                shutil.copy2(source, target, follow_symlinks=True)
                print(f"Staged macOS dependency {target.name}")
            if target not in visited:
                queued.append(target)
    for binary in sorted(visited):
        for dependency in original_deps[binary]:
            if system_macos_dependency(dependency):
                continue
            name = Path(dependency).name
            target = folder / name
            if not target.exists():
                raise RuntimeError(f"{binary.name}: missing dependency {name}")
            replacement = "@loader_path/" + name
            if dependency != replacement:
                run("install_name_tool", "-change", dependency, replacement, str(binary))
        if binary.name.endswith(".dylib"):
            run("install_name_tool", "-id", "@loader_path/" + binary.name, str(binary))
        run("codesign", "--force", "--sign", "-", "--timestamp=none", str(binary))
    for binary in sorted(visited):
        for dependency in mac_dependencies(binary):
            if not system_macos_dependency(dependency):
                expected = "@loader_path/" + Path(dependency).name
                if dependency != expected or not (folder / Path(dependency).name).is_file():
                    raise RuntimeError(f"{binary.name}: unresolved macOS dependency {dependency}")
    print(f"macOS runtime closure verified in {folder}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["Linux", "macOS"], required=True)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--search-dir", type=Path, action="append", default=[])
    args = parser.parse_args()
    folder = args.directory.resolve(strict=True)
    materialize_symlinks(folder)
    if args.platform == "Linux":
        stage_linux(folder)
    else:
        stage_macos(folder, [p.resolve() for p in args.search_dir if p.is_dir()])


if __name__ == "__main__":
    main()

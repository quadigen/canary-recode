#!/usr/bin/env python3
"""Deterministic and path-safe bundles for prebuilt Kinemium runtimes.

This intentionally packages an existing binary; it does not recompile/link away
unused engine code. See README.md for native dependency and platform limits.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import stat
import sys
import zipfile

FORMAT_VERSION = 1
METADATA = "kinemium-package.json"
MODES = ("offline", "lan", "dedicated", "mod")
ARCHIVE_DATE = (1980, 1, 1, 0, 0, 0)
MAX_MANIFEST = 1024 * 1024
MAX_MEMBERS = 10000
MAX_VERIFY_BYTES = 16 * 1024 * 1024 * 1024


class PackageError(ValueError):
    pass


def path_in_archive(raw: object) -> str:
    if not isinstance(raw, str) or not raw or "\x00" in raw or "\\" in raw:
        raise PackageError(f"invalid archive path: {raw!r}")
    if raw.startswith("/") or re.match(r"^[a-zA-Z]:", raw):
        raise PackageError(f"absolute archive path: {raw!r}")
    parts = raw.split("/")
    if any(piece in ("", ".", "..") for piece in parts):
        raise PackageError(f"unsafe archive path: {raw!r}")
    return str(PurePosixPath(*parts))


def read_input(root: Path, name: object) -> bytes:
    rel = path_in_archive(name)
    path = root.joinpath(*rel.split("/"))
    current = root
    for part in rel.split("/"):
        current = current / part
        if current.is_symlink():
            raise PackageError(f"symlink input is forbidden: {rel}")
    if not path.is_file() or not stat.S_ISREG(path.stat().st_mode):
        raise PackageError(f"missing/nonregular input file: {rel}")
    if not path.resolve().is_relative_to(root.resolve()):
        raise PackageError(f"file escaped source root: {rel}")
    return path.read_bytes()


def read_binary(path: Path) -> bytes:
    if path.is_symlink() or not path.is_file() or not stat.S_ISREG(path.stat().st_mode):
        raise PackageError(f"missing, symlink or nonregular runtime: {path}")
    return path.read_bytes()


def parse_config(config_path: Path) -> dict:
    if not config_path.is_file() or config_path.stat().st_size > MAX_MANIFEST:
        raise PackageError("manifest absent or exceeds 1 MiB")
    try:
        obj = json.loads(config_path.read_text(encoding="utf-8"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise PackageError(f"invalid JSON manifest: {exc}") from exc
    if not isinstance(obj, dict) or obj.get("schema") != 1:
        raise PackageError("manifest must be a JSON object with schema=1")
    for field in ("name", "version"):
        value = obj.get(field)
        if not isinstance(value, str) or not (1 <= len(value) <= 100):
            raise PackageError(f"{field} must be a string of 1..100 characters")
        if any(ord(char) < 32 for char in value):
            raise PackageError(f"{field} contains a control character")
    for field in ("files", "mods"):
        if field in obj and (not isinstance(obj[field], list) or len(obj[field]) > MAX_MEMBERS):
            raise PackageError(f"{field} must be an array of at most {MAX_MEMBERS}")
    return obj


def shell_launch(runtime: str, map_path: str, mode: str, port: int, address: str) -> tuple[str, str]:
    args = (["--singleplayer"] if mode == "offline" else ["--server"])
    args += ["--map", map_path]
    if mode != "offline":
        args += ["--port", str(port), "--address", address]
    if mode == "lan":
        args.append("--window")
    quoted = " ".join(shlex.quote(arg) for arg in args)
    command = f"./{runtime}"
    sh = '#!/bin/sh\nset -eu\ncd -- "$(dirname -- "$0")"\nexport LD_LIBRARY_PATH="$PWD/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexport DYLD_LIBRARY_PATH="$PWD/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"\nexec ' + shlex.quote(command) + " " + quoted + ' "$@"\n'
    cmd = '@echo off\r\ncd /d "%~dp0"\r\n"' + runtime.replace("/", "\\") + '" ' + " ".join(
        '"' + arg.replace('"', '""') + '"' for arg in args
    ) + ' %*\r\n'
    return sh, cmd


def add_member(members: dict[str, tuple[bytes, bool]], path: str, data: bytes, executable=False):
    path = path_in_archive(path)
    if path in members or path == METADATA:
        raise PackageError(f"duplicate or reserved bundle path: {path}")
    members[path] = (data, executable)


def make_bundle(config_path: Path, root: Path, engine: Path | None, mode: str,
                platform: str, port: int, address: str,
                libraries: list[Path] | None = None) -> dict[str, tuple[bytes, bool]]:
    config = parse_config(config_path)
    if mode not in MODES:
        raise PackageError(f"unknown mode: {mode}")
    if not (1 <= port <= 65535):
        raise PackageError("port must be 1..65535")
    if not address or re.search(r"[^a-zA-Z0-9.:_-]", address):
        raise PackageError("invalid network bind address")
    if len(platform) > 64 or not re.fullmatch(r"[a-zA-Z0-9._-]+", platform):
        raise PackageError("platform must contain only letters, digits, dots, underscores or hyphens")

    members: dict[str, tuple[bytes, bool]] = {}
    runtime = ""
    if mode != "mod":
        if engine is None:
            raise PackageError("--engine is required for runtime bundles")
        runtime = "bin/kinemium.exe" if engine.name.lower().endswith(".exe") else "bin/kinemium"
        add_member(members, runtime, read_binary(engine), executable=True)
        map_source = config.get("map")
        if not isinstance(map_source, str) or not map_source.lower().endswith(".kine"):
            raise PackageError("runtime bundles require a .kine map")
        map_rel = path_in_archive(map_source)
        map_path = "content/" + map_rel
        add_member(members, map_path, read_input(root, map_rel))
    else:
        map_path = None
        if config.get("map") is not None:
            raise PackageError("mod bundles cannot declare an executable map")

    for library in libraries or []:
        if mode == "mod":
            raise PackageError("mod bundles cannot contain runtime libraries")
        if library.name.lower().endswith(".dll"):
            destination = "bin/" + path_in_archive(library.name)
        else:
            destination = "lib/" + path_in_archive(library.name)
        add_member(members, destination, read_binary(library))

    for key, prefix in (("files", ""), ("mods", "mods/")):
        for i, entry in enumerate(config.get(key, [])):
            if not isinstance(entry, dict) or not isinstance(entry.get("source"), str):
                raise PackageError(f"{key}[{i}] must contain a source path")
            source = path_in_archive(entry["source"])
            destination = path_in_archive(entry.get("destination", source))
            if prefix and destination.startswith(prefix):
                raise PackageError(f"{key}[{i}] destination must not include the mods/ prefix")
            add_member(members, prefix + destination, read_input(root, source))

    if mode != "mod":
        sh, cmd = shell_launch(runtime, map_path, mode, port, address)
        add_member(members, "run.sh", sh.encode("utf-8"), executable=True)
        add_member(members, "run.cmd", cmd.encode("utf-8"))

    contents = []
    for path, (data, executable) in sorted(members.items()):
        contents.append({"path": path, "size": len(data),
                         "sha256": hashlib.sha256(data).hexdigest(), "executable": executable})
    metadata = {
        "schema": FORMAT_VERSION, "name": config["name"], "version": config["version"],
        "mode": mode, "platform": platform, "map": map_path, "files": contents,
    }
    members[METADATA] = ((json.dumps(metadata, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode(), False)
    return members


def write_archive(target: Path, members: dict[str, tuple[bytes, bool]]) -> None:
    if not target.parent.is_dir():
        raise PackageError(f"output directory does not exist: {target.parent}")
    tmp = target.with_name(target.name + ".tmp-" + str(os.getpid()))
    try:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED,
                             compresslevel=9, allowZip64=True) as out:
            for name in sorted(members):
                data, executable = members[name]
                entry = zipfile.ZipInfo(name, ARCHIVE_DATE)
                entry.create_system = 3
                entry.external_attr = ((0o100755 if executable else 0o100644) << 16)
                entry.compress_type = zipfile.ZIP_DEFLATED
                out.writestr(entry, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        tmp.replace(target)
    finally:
        if tmp.exists():
            tmp.unlink()


def verify_archive(package: Path) -> dict:
    try:
        with zipfile.ZipFile(package) as archive:
            infos = archive.infolist()
            if len(infos) > MAX_MEMBERS + 5:
                raise PackageError("too many bundle members")
            names = [info.filename for info in infos]
            if len(names) != len(set(names)):
                raise PackageError("archive contains duplicate paths")
            if METADATA not in names:
                raise PackageError("package metadata missing")
            for info in infos:
                path_in_archive(info.filename)
                if stat.S_ISLNK(info.external_attr >> 16):
                    raise PackageError("archive contains symlink entry")
                if info.file_size > MAX_VERIFY_BYTES:
                    raise PackageError("oversized archive member")
            if sum(info.file_size for info in infos) > MAX_VERIFY_BYTES:
                raise PackageError("uncompressed archive exceeds safety limit")
            raw = archive.read(METADATA)
            if len(raw) > MAX_MANIFEST:
                raise PackageError("package metadata exceeds 1 MiB")
            manifest = json.loads(raw)
            if not isinstance(manifest, dict) or manifest.get("schema") != FORMAT_VERSION:
                raise PackageError("invalid package schema")
            expected = manifest.get("files")
            if not isinstance(expected, list):
                raise PackageError("invalid package entries")
            observed = set()
            for item in expected:
                if not isinstance(item, dict) or not isinstance(item.get("path"), str):
                    raise PackageError("invalid metadata member")
                name = path_in_archive(item["path"])
                if name in observed or name == METADATA:
                    raise PackageError("duplicate or reserved metadata path")
                observed.add(name)
                digest = hashlib.sha256()
                count = 0
                with archive.open(name) as source:
                    while True:
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        count += len(chunk)
                        digest.update(chunk)
                if count != item.get("size") or digest.hexdigest() != item.get("sha256"):
                    raise PackageError(f"hash/size mismatch: {name}")
            if observed | {METADATA} != set(names):
                raise PackageError("unlisted members found in archive")
            return manifest
    except (OSError, zipfile.BadZipFile, KeyError, ValueError, json.JSONDecodeError) as exc:
        if isinstance(exc, PackageError):
            raise
        raise PackageError(f"invalid or corrupted package: {exc}") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    pack = sub.add_parser("pack", help="create a deterministic .zip Kinemium bundle")
    pack.add_argument("--config", type=Path, required=True)
    pack.add_argument("--root", type=Path, required=True, help="source root; input paths stay within it")
    pack.add_argument("--engine", type=Path, help="prebuilt Kinemium runtime, required except for mods")
    pack.add_argument("--library", type=Path, action="append", default=[], help="required runtime .so/.dylib/.dll; repeatable")
    pack.add_argument("--mode", choices=MODES, required=True)
    pack.add_argument("--platform", default=sys.platform)
    pack.add_argument("--address", default="0.0.0.0")
    pack.add_argument("--port", type=int, default=7777)
    pack.add_argument("--out", type=Path, required=True)
    verify = sub.add_parser("verify", help="validate archive paths, hashes and manifest")
    verify.add_argument("archive", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "pack":
            members = make_bundle(args.config, args.root.resolve(strict=True), args.engine,
                                  args.mode, args.platform, args.port, args.address, args.library)
            write_archive(args.out, members)
            print(f"PACKAGED {args.mode} {len(members)} entries => {args.out}")
        else:
            manifest = verify_archive(args.archive)
            print(f"VERIFIED {manifest['mode']} {len(manifest['files'])} files {manifest['name']}")
    except (PackageError, OSError) as exc:
        print(f"package error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

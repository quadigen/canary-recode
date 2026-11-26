import argparse
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def pkg_config(*args):
    return shlex.split(subprocess.check_output(["pkg-config", *args], text=True))


def build(output):
    system = platform.system()
    if system == "Linux":
        library = "libkinemium.so"
        flags = f"-L{ROOT / 'vendor/build/lib'} -Wl,-rpath,$ORIGIN:$ORIGIN/../vendor/build/lib"
    elif system == "Darwin":
        library = "libkinemium.dylib"
        flags = f"-L{ROOT / 'vendor/build/lib'} -Wl,-rpath,@loader_path"
    else:
        raise RuntimeError(f"Unsupported host: {system}")

    for directory in ("include", "lib", "examples/plugin", "bin",
                      "plugins/native.example", "plugins/native.secondary",
                      "lib/pkgconfig", "lib/cmake/Kinemium"):
        (output / directory).mkdir(parents=True, exist_ok=True)
    (ROOT / "build").mkdir(exist_ok=True)

    run("python3", ROOT / "tools/generate_kinemium_runtime_loader.py", "--check")
    run("odin", "build", ROOT / "src/shared_library", "-build-mode:shared",
        f"-out:{ROOT / 'build' / library}", f"-extra-linker-flags:{flags}")
    shutil.copy2(ROOT / "build" / library, output / "lib" / library)

    for filename in ("kinemium.h", "kinemium_plugin.h", "kinemium_runtime.h",
                     "kinemium_runtime_symbols.h"):
        shutil.copy2(ROOT / "include" / filename, output / "include" / filename)
    samples = {
        "main.c": "examples/kinemium_sdk/main.c",
        "headless.c": "examples/kinemium_sdk/headless.c",
        "windowed.c": "examples/kinemium_sdk/windowed.c",
        "kinemium_runtime.c": "src/kinemium_runtime.c",
        "dynamic.c": "examples/kinemium_sdk/dynamic.c",
        "gpu_compute.c": "examples/kinemium_sdk/gpu_compute.c",
        "dynamic_windowed.c": "examples/kinemium_sdk/dynamic_windowed.c",
        "plugin/main.c": "examples/kinemium_sdk/plugin/main.c",
        "plugin/secondary.c": "examples/kinemium_sdk/plugin/secondary.c",
        "CMakeLists.txt": "examples/kinemium_sdk/CMakeLists.txt",
    }
    for target, source in samples.items():
        shutil.copy2(ROOT / source, output / "examples" / target)
    shutil.copy2(ROOT / "docs/sdk/README.md", output / "README.md")
    (output / "lib/pkgconfig/kinemium.pc").write_text(
        "prefix=${pcfiledir}/../..\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\n"
        "\nName: kinemium\nDescription: Kinemium Unified Native C SDK ABI 2\n"
        "Version: 2.0.0\nLibs: -L${libdir} -lkinemium\nCflags: -I${includedir}\n"
    )
    shutil.copy2(ROOT / "examples/kinemium_sdk/KinemiumConfig.cmake",
                 output / "lib/cmake/Kinemium/KinemiumConfig.cmake")
    socket = ROOT / "vendor/build/lib/libGameNetworkingSockets.so"
    if socket.is_file():
        shutil.copy2(socket.resolve(), output / "lib" / socket.name)
    if shutil.which("strip") and os.environ.get("KINEMIUM_SDK_KEEP_SYMBOLS") != "1":
        subprocess.run(["strip", "--strip-debug", str(output / "lib" / library)], check=False)

    if system == "Linux":
        inc = ["-I" + str(output / "include")]
        examples = output / "examples"
        binaries = output / "bin"
        libdir = output / "lib"
        runtime = examples / "kinemium_runtime.c"
        run("cc", "-std=c11", "-Wall", "-Wextra", "-Wpedantic", "-Werror",
            *inc, runtime, examples / "dynamic.c", "-ldl",
            "-o", binaries / "kinemium_sdk_dynamic")
        run("cc", "-std=c11", "-Wall", "-Wextra", "-Wpedantic", "-Werror",
            *inc, runtime, examples / "gpu_compute.c", "-ldl",
            "-o", binaries / "kinemium_sdk_gpu_compute")
        run("cc", "-std=c11", "-Wall", "-Wextra", "-Werror", *inc,
            examples / "headless.c", "-L" + str(libdir), "-lkinemium",
            "-Wl,-rpath,$ORIGIN/../lib", "-o", binaries / "kinemium_sdk_headless")
        if subprocess.run(["pkg-config", "--exists", "sdl3"]).returncode == 0:
            cflags = pkg_config("--cflags", "sdl3")
            libs = pkg_config("--libs", "sdl3")
            run("cc", "-std=c11", "-Wall", "-Wextra", "-Werror", *inc, *cflags,
                examples / "main.c", "-L" + str(libdir), "-lkinemium", *libs,
                "-Wl,-rpath,$ORIGIN/../lib", "-o", binaries / "kinemium_sdk_example")
            run("cc", "-std=c11", "-Wall", "-Wextra", "-Wpedantic", "-Werror", *inc,
                *cflags, runtime, examples / "dynamic_windowed.c", *libs, "-ldl",
                "-o", binaries / "kinemium_sdk_dynamic_windowed")
            run("cc", "-std=c11", "-Wall", "-Wextra", "-Werror", *inc, *cflags,
                examples / "windowed.c", "-L" + str(libdir), "-lkinemium", *libs,
                "-Wl,-rpath,$ORIGIN/../lib", "-o", binaries / "kinemium_sdk_windowed")
        else:
            print("SDL3 development files unavailable; skipping windowed examples")

        for plugin, source in (("native.example", "main.c"),
                               ("native.secondary", "secondary.c")):
            directory = output / "plugins" / plugin
            soname = plugin.replace(".", "_") + ".so"
            run("cc", "-std=c11", "-fPIC", "-shared", "-Wall", "-Wextra", "-Werror",
                *inc, examples / "plugin" / source, "-o", directory / soname)
            manifest = {
                "id": plugin,
                "name": "Native Example" if plugin == "native.example" else "Secondary Native Plugin",
                "version": "1.0.0", "api": 2, "api_minor": 0,
                "library": soname, "entry": "Kinemium_PluginEntry", "enabled": True,
            }
            (directory / "extension.json").write_text(json.dumps(manifest) + "\n")

    run("python3", ROOT / "tests/sdk/verify_exports.py",
        output / "include/kinemium.h", output / "lib" / library)
    print(f"Kinemium SDK package: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?", type=Path, default=ROOT / "dist/kinemium")
    args = parser.parse_args()
    build(args.output.resolve())

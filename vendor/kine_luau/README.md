# Odin Luau bridge

Luau exposes a C-style API with C++ linkage. This bridge gives the Odin bindings
stable C symbols and builds Luau with the static MSVC runtime expected by Odin.

From a Visual Studio developer terminal on Windows:

```powershell
cmake -S vendor/kine_luau -B build-odin-luau -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
cmake --build build-odin-luau --target kine_luau -j 4
odin build src -out:build/KinemiumOdin.exe
```

The top-level CMake build also includes `kine_luau` for native targets.

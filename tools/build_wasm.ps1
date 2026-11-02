param(
    [string]$OutputDirectory = "build/web",
    [string]$BuildTarget = "editor",
    [string]$ClientAddress = "",
    [string]$ClientPort = "",
    [string]$Shell = "index.html"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $repoRoot $OutputDirectory
$nativeBuild = Join-Path $repoRoot "build/web-native"
$nativeLib = Join-Path $nativeBuild "lib"
$configuredEmsdk = if ($env:EMSDK) { $env:EMSDK } else { "" }
$emsdkRoot = if ($configuredEmsdk -and (Test-Path -LiteralPath (Join-Path $configuredEmsdk "upstream/emscripten/emcc.bat"))) {
    $configuredEmsdk
} else {
    Join-Path $repoRoot ".tools/emsdk"
}
$emcc = Join-Path $emsdkRoot "upstream/emscripten/emcc.bat"
$emcmake = Join-Path $emsdkRoot "upstream/emscripten/emcmake.bat"

if (!(Test-Path -LiteralPath $emcc) -or !(Test-Path -LiteralPath $emcmake)) {
    throw "Emscripten is required. Set EMSDK or install it at .tools/emsdk."
}
$env:EMSDK_QUIET = "1"
$emsdkEnvironment = & cmd.exe /d /c "call `"$(Join-Path $emsdkRoot 'emsdk_env.bat')`" >nul && set"
foreach ($line in $emsdkEnvironment) {
    if ($line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

$odinCommand = Get-Command odin -ErrorAction Stop
$odinRoot = Split-Path -Parent $odinCommand.Source
$odinRuntime = Join-Path $odinRoot "core/sys/wasm/js/odin.js"
$systemLib = Join-Path $emsdkRoot "upstream/emscripten/cache/sysroot/lib/wasm32-emscripten"
New-Item -ItemType Directory -Force $outputPath, $nativeBuild, $nativeLib | Out-Null

# Build the real native engine dependencies for wasm32 and combine each wrapper
# with its implementation so Odin consumes normal relocatable wasm objects.
& $emcmake cmake -S (Join-Path $repoRoot "cmake/web-native") -B $nativeBuild -G Ninja -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build $nativeBuild --config Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $emcc -r "-Wl,--whole-archive" (Join-Path $nativeLib "libkine_luau.a") "-Wl,--no-whole-archive" `
    (Join-Path $nativeBuild "luau/libLuau.VM.a") (Join-Path $nativeBuild "luau/libLuau.Compiler.a") `
    (Join-Path $nativeBuild "luau/libLuau.Ast.a") (Join-Path $nativeBuild "luau/libLuau.Bytecode.a") `
    (Join-Path $nativeBuild "luau/libLuau.Common.a") -o (Join-Path $nativeLib "kine_luau_web.o")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $emcc -r "-Wl,--whole-archive" (Join-Path $nativeLib "libJoltWrapper.a") "-Wl,--no-whole-archive" `
    (Join-Path $nativeLib "libJolt.a") -o (Join-Path $nativeLib "kine_jolt_web.o")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $emcc -r "-Wl,--whole-archive" (Join-Path $nativeLib "libRecastWrapper.a") "-Wl,--no-whole-archive" `
    (Join-Path $nativeLib "libRecast.a") (Join-Path $nativeLib "libDetour.a") -o (Join-Path $nativeLib "kine_recast_web.o")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $emcc -c (Join-Path $repoRoot "cmake/web-native/luacode_link.c") -o (Join-Path $nativeLib "kine_luacode_link.o")
& $emcc -c (Join-Path $repoRoot "cmake/web-native/lualib_link.c") -o (Join-Path $nativeLib "kine_lualib_link.o")
& $emcc -c (Join-Path $repoRoot "cmake/web-native/web_allocator.c") -o (Join-Path $nativeLib "web_allocator.o")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$runtimeArchives = @("libc++.a", "libc++abi.a", "libc.a", "libcompiler_rt.a")
foreach ($archive in $runtimeArchives) {
    Copy-Item -LiteralPath (Join-Path $systemLib $archive) -Destination (Join-Path $nativeLib $archive) -Force
}
$linkFlags = @(
    "--allow-multiple-definition", "--export-table",
    # Emscripten setjmp/longjmp + C++ exception runtime (Luau/Jolt throw across
    # the JS boundary). The browser shell implements __cxa_* / invoke_* in JS and
    # calls these wasm helpers, so they must be exported and force-linked.
    "--export=setThrew", "--export=_emscripten_tempret_set", "--export=_emscripten_tempret_get",
    "--export=__cxa_increment_exception_refcount", "--export=__cxa_decrement_exception_refcount",
    "--export=__cxa_can_catch", "--export=__cxa_get_exception_ptr",
    "--export=emscripten_stack_get_current", "--export=_emscripten_stack_restore",
    "--undefined=setThrew", "--undefined=_emscripten_tempret_set",
    "--undefined=__cxa_increment_exception_refcount", "--undefined=__cxa_decrement_exception_refcount",
    "--undefined=__cxa_can_catch", "--undefined=__cxa_get_exception_ptr",
    "--undefined=emscripten_stack_get_current", "--undefined=_emscripten_stack_restore",
    "--wrap=malloc", "--wrap=free", "--wrap=calloc", "--wrap=realloc",
    "--wrap=posix_memalign", "--wrap=strcmp", (Join-Path $nativeLib "web_allocator.o"),
    (Join-Path $nativeLib "libc++.a"), (Join-Path $nativeLib "libc++abi.a"),
    (Join-Path $nativeLib "libc.a"), (Join-Path $nativeLib "libcompiler_rt.a")
) -join " "

# Embed the editor UI for the browser. The Web target cannot fetch the desktop
# editor ZIP at runtime, so pack a kinemium-editor checkout's internal tree into
# the binary at compile time. A client build never embeds the editor.
$editorModules = if ($env:KINEMIUM_EDITOR_MODULES) { $env:KINEMIUM_EDITOR_MODULES } else {
    Join-Path (Split-Path -Parent $repoRoot) "kinemium-editor/internal"
}
$odinArguments = @(
    "build", (Join-Path $repoRoot "src"), "-target:js_wasm32", "-o:speed",
    "-define:BUILD_TARGET=$BuildTarget",
    "-out:$(Join-Path $outputPath 'kinemium_engine.wasm')",
    "-extra-linker-flags:$linkFlags"
)
if ($BuildTarget -eq "editor" -and (Test-Path -LiteralPath $editorModules)) {
    $resolvedEditor = (Resolve-Path -LiteralPath $editorModules).Path
    Write-Host "Embedding editor modules from $resolvedEditor"
    $odinArguments += "-define:EDITOR_MODULES=$resolvedEditor"

    $editorComponents = Join-Path $editorModules "Components"
    if (Test-Path -LiteralPath $editorComponents) {
        $resolvedComponents = (Resolve-Path -LiteralPath $editorComponents).Path
        Write-Host "Embedding editor components from $resolvedComponents"
        $odinArguments += "-define:EDITOR_COMPONENTS=$resolvedComponents"
    }
} elseif ($BuildTarget -eq "editor") {
    Write-Host "No kinemium-editor checkout found; building without the embedded editor UI"
}
if ($ClientAddress) { $odinArguments += "-define:KINE_ADDRESS=$ClientAddress" }
if ($ClientPort) { $odinArguments += "-define:KINE_PORT=$ClientPort" }

& $odinCommand.Source @odinArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Stage the desktop shell and official CanvasKit/Filament browser distributions.
Copy-Item -LiteralPath (Join-Path $repoRoot "web/$Shell") -Destination $outputPath -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "web/app.css") -Destination $outputPath -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "web/app.js") -Destination $outputPath -Force
Copy-Item -LiteralPath $odinRuntime -Destination (Join-Path $outputPath "odin.js") -Force

$canvasKitRoot = Join-Path $repoRoot ".cache/web-deps/node_modules/canvaskit-wasm/bin"
if (!(Test-Path -LiteralPath (Join-Path $canvasKitRoot "canvaskit.wasm"))) {
    npm install --prefix (Join-Path $repoRoot ".cache/web-deps") --no-save canvaskit-wasm@0.42.0
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
$canvasKitOutput = Join-Path $outputPath "canvaskit"
New-Item -ItemType Directory -Force $canvasKitOutput | Out-Null
Copy-Item -LiteralPath (Join-Path $canvasKitRoot "canvaskit.js") -Destination $canvasKitOutput -Force
Copy-Item -LiteralPath (Join-Path $canvasKitRoot "canvaskit.wasm") -Destination $canvasKitOutput -Force
$fontOutput = Join-Path $outputPath "fonts"
New-Item -ItemType Directory -Force $fontOutput | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot "src/engine/assets/fonts/Roboto-VariableFont_wdth_wght.ttf") `
    -Destination (Join-Path $fontOutput "Roboto.ttf") -Force

$filamentCache = Join-Path $repoRoot ".cache/filament-web"
$filamentArchive = Join-Path $filamentCache "filament-v1.74.0-web.tgz"
if (!(Test-Path -LiteralPath (Join-Path $filamentCache "filament.wasm"))) {
    New-Item -ItemType Directory -Force $filamentCache | Out-Null
    Invoke-WebRequest "https://github.com/google/filament/releases/download/v1.74.0/filament-v1.74.0-web.tgz" -OutFile $filamentArchive
    tar -xzf $filamentArchive -C $filamentCache
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
$filamentOutput = Join-Path $outputPath "filament"
New-Item -ItemType Directory -Force $filamentOutput | Out-Null
Copy-Item -LiteralPath (Join-Path $filamentCache "filament.js") -Destination $filamentOutput -Force
Copy-Item -LiteralPath (Join-Path $filamentCache "filament.wasm") -Destination $filamentOutput -Force

$matc = if ($env:FILAMENT_MATC) { $env:FILAMENT_MATC } else {
    Get-ChildItem -Path (Split-Path -Parent $repoRoot) -Filter "matc.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (!$matc) { throw "Filament matc is required. Set FILAMENT_MATC to matc.exe." }
& $matc -a opengl -p mobile -o (Join-Path $filamentOutput "kine_web.filamat") (Join-Path $repoRoot "web/kine_web.mat")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$wasm = Get-Item (Join-Path $outputPath "kinemium_engine.wasm")
Write-Host "KINEMIUM_WASM_BUILD_PASSED $($wasm.FullName) ($($wasm.Length) bytes)"

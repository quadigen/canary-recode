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
# Emscripten 7 ships native Windows .exe launchers instead of .bat files.
# Keep support for older SDKs while resolving every tool from the same SDK.
function Find-EmscriptenTool([string]$Root, [string]$Name) {
    foreach ($extension in @(".exe", ".bat", ".cmd")) {
        $candidate = Join-Path $Root "upstream/emscripten/$Name$extension"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}
$emsdkRoot = $null
foreach ($candidate in @($env:EMSDK, (Join-Path $repoRoot ".tools/emsdk"))) {
    if ($candidate -and (Find-EmscriptenTool $candidate "emcc") -and
        (Find-EmscriptenTool $candidate "emcmake")) {
        $emsdkRoot = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if (!$emsdkRoot) {
    throw "Emscripten is required. Set EMSDK or install it at .tools/emsdk."
}
$env:EMSDK_QUIET = "1"
$emsdkEnvironment = & cmd.exe /d /c "call `"$(Join-Path $emsdkRoot 'emsdk_env.bat')`" >nul && set"
if ($LASTEXITCODE -ne 0) { throw "Failed to initialize Emscripten environment" }
foreach ($line in $emsdkEnvironment) {
    if ($line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}
$emcc = Find-EmscriptenTool $emsdkRoot "emcc"
$emcmake = Find-EmscriptenTool $emsdkRoot "emcmake"
$emconfig = Find-EmscriptenTool $emsdkRoot "em-config"
$embuilder = Find-EmscriptenTool $emsdkRoot "embuilder"
if (!$emconfig -or !$embuilder) { throw "Emscripten SDK is missing em-config or embuilder" }

$odinCommand = Get-Command odin -ErrorAction Stop
$odinRoot = (& $odinCommand.Source root).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not locate Odin SDK" }
$odinRuntime = Join-Path $odinRoot "core/sys/wasm/js/odin.js"
$cacheRoot = (& $emconfig CACHE).Trim()
if ($LASTEXITCODE -ne 0 -or !$cacheRoot) { throw "Could not locate Emscripten cache" }
$systemLib = Join-Path $cacheRoot "sysroot/lib/wasm32-emscripten"
New-Item -ItemType Directory -Force $outputPath, $nativeBuild, $nativeLib | Out-Null

# Build the real native engine dependencies for wasm32 and combine each wrapper
# with its implementation so Odin consumes normal relocatable wasm objects.
& $emcmake cmake -S (Join-Path $repoRoot "cmake/web-native") -B $nativeBuild -G Ninja -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build $nativeBuild --config Release --target kine_luau JoltWrapper RecastWrapper
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
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $emcc -c (Join-Path $repoRoot "cmake/web-native/lualib_link.c") -o (Join-Path $nativeLib "kine_lualib_link.o")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $emcc -c (Join-Path $repoRoot "cmake/web-native/lexer_link.c") -o (Join-Path $nativeLib "kine_lexer_link.o")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $emcc -c (Join-Path $repoRoot "cmake/web-native/webview_link.c") -o (Join-Path $nativeLib "kine_webview_link.o")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $emcc -c (Join-Path $repoRoot "cmake/web-native/web_allocator.c") -o (Join-Path $nativeLib "web_allocator.o")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Explicitly build the non-threaded JS-exception runtime used by Odin's
# custom browser host. A default em++ link may select noexcept archives.
$versionText = (& $emcc --version | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or $versionText -notmatch '\b(\d+)\.\d+\.\d+\b') {
    throw "Could not determine Emscripten version: $versionText"
}
$runtimeNames = @("libc++", "libc++abi", "libc")
if ([int]$matches[1] -ge 7) {
    # Emscripten 7 split compiler_rt into builtins and low-level runtime.
    $runtimeNames += @("libemcc", "libclang_rt.builtins")
} else {
    $runtimeNames += "libcompiler_rt"
}
& $embuilder build @runtimeNames
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$runtimeArchives = @($runtimeNames | ForEach-Object { "$_.a" })
foreach ($archive in $runtimeArchives) {
    $source = Join-Path $systemLib $archive
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing Emscripten runtime archive: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $nativeLib $archive) -Force
}
$linkFlags = @(
    "--allow-multiple-definition", "--export-table", "--strip-debug", "--export=__wasm_call_ctors",
    "--export=setThrew", "--export=_emscripten_tempret_set", "--export=_emscripten_tempret_get",
    "--export=__cxa_increment_exception_refcount", "--export=__cxa_decrement_exception_refcount",
    "--export=__cxa_can_catch", "--export=__cxa_get_exception_ptr",
    "--export=emscripten_stack_get_current", "--export=_emscripten_stack_restore",
    "--undefined=setThrew", "--undefined=_emscripten_tempret_set",
    "--undefined=__cxa_increment_exception_refcount", "--undefined=__cxa_decrement_exception_refcount",
    "--undefined=__cxa_can_catch", "--undefined=__cxa_get_exception_ptr",
    "--undefined=emscripten_stack_get_current", "--undefined=_emscripten_stack_restore",
    "--wrap=malloc", "--wrap=free", "--wrap=calloc", "--wrap=realloc",
    "--wrap=posix_memalign", "--wrap=strcmp", "build/web-native/lib/web_allocator.o"
)
$linkFlags += @($runtimeArchives | ForEach-Object { "build/web-native/lib/$_" })
$linkFlags = $linkFlags -join " "

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
    $editorPackage = Join-Path $repoRoot "build/web-native/editor-modules.kemp"
    & python (Join-Path $repoRoot "tools/pack_editor_modules.py") $resolvedEditor $editorPackage
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $odinArguments += "-define:EDITOR_PACKAGE=$editorPackage"
} elseif ($BuildTarget -eq "editor") {
    throw "Editor modules not found at $editorModules. Set KINEMIUM_EDITOR_MODULES or clone kinemium-editor next to this repository."
}
if ($ClientAddress) { $odinArguments += "-define:KINE_ADDRESS=$ClientAddress" }
if ($ClientPort) { $odinArguments += "-define:KINE_PORT=$ClientPort" }

Push-Location $repoRoot
try {
    & $odinCommand.Source @odinArguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally { Pop-Location }

# Stage the desktop shell and official CanvasKit/Babylon.js browser distributions.
Copy-Item -LiteralPath (Join-Path $repoRoot "web/$Shell") -Destination (Join-Path $outputPath "index.html") -Force
if ($Shell -ne "index.html") {
    Copy-Item -LiteralPath (Join-Path $repoRoot "web/$Shell") -Destination $outputPath -Force
}
Copy-Item -LiteralPath (Join-Path $repoRoot "web/app.css") -Destination $outputPath -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "web/app.js") -Destination $outputPath -Force
Copy-Item -LiteralPath (Join-Path $repoRoot "web/babylon_backend.js") -Destination $outputPath -Force
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

# Pin and stage the browser renderer locally, so the shipped web runtime
# doesn't request a CDN or require the native Filament material compiler.
$babylonVersion = "9.37.1"
$babylonCache = Join-Path $repoRoot ".cache/babylon-web"
$babylonRoot = Join-Path $babylonCache "node_modules/babylonjs"
$babylonPackage = Join-Path $babylonRoot "package.json"
$installedVersion = if (Test-Path -LiteralPath $babylonPackage) {
    (Get-Content -LiteralPath $babylonPackage -Raw | ConvertFrom-Json).version
} else { "" }
if ($installedVersion -ne $babylonVersion -or !(Test-Path -LiteralPath (Join-Path $babylonRoot "babylon.js"))) {
    npm install --prefix $babylonCache --no-save --package-lock=false --ignore-scripts "babylonjs@$babylonVersion"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
$babylonOutput = Join-Path $outputPath "babylon"
New-Item -ItemType Directory -Force $babylonOutput | Out-Null
Copy-Item -LiteralPath (Join-Path $babylonRoot "babylon.js") -Destination $babylonOutput -Force
foreach ($notice in @("license.md", "NOTICE.md")) {
    if (Test-Path -LiteralPath (Join-Path $babylonRoot $notice)) {
        Copy-Item -LiteralPath (Join-Path $babylonRoot $notice) -Destination $babylonOutput -Force
    }
}
# Existing output directories may contain the legacy web backend.
$legacyRenderer = Join-Path $outputPath "filament"
if (Test-Path -LiteralPath $legacyRenderer) {
    Remove-Item -LiteralPath $legacyRenderer -Recurse -Force
}

python (Join-Path $repoRoot "tools/stage_web_assets.py") $outputPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$wasm = Get-Item (Join-Path $outputPath "kinemium_engine.wasm")
Write-Host "KINEMIUM_WASM_BUILD_PASSED $($wasm.FullName) ($($wasm.Length) bytes)"

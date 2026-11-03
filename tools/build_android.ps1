param(
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$NdkVersion = "30.0.16248370",
    [int]$ApiLevel = 30,
    [string[]]$Abis = @("arm64-v8a", "x86_64"),
    [switch]$UsePrebuiltSkia,
    [switch]$PrepareOnly
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $AndroidSdk) { $AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$ndk = Join-Path $AndroidSdk "ndk\$NdkVersion"
if (-not (Test-Path (Join-Path $ndk "build\cmake\android.toolchain.cmake"))) {
    throw "Android NDK $NdkVersion was not found under $AndroidSdk"
}
$env:ANDROID_NDK_HOME = $ndk
$odinRoot = (& odin root).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not locate the Odin SDK" }

# The Android job does not enter a Visual Studio shell. Prefer Ninja on PATH,
# then the copy shipped with the Android SDK's CMake package.
$ninjaCommand = Get-Command ninja -ErrorAction SilentlyContinue
$ninjaExecutable = if ($null -ne $ninjaCommand) { $ninjaCommand.Source } else { "" }
if (-not $ninjaExecutable) {
    $sdkNinja = Get-ChildItem -Path (Join-Path $AndroidSdk 'cmake/*/bin/ninja.exe') -File -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($sdkNinja) { $ninjaExecutable = $sdkNinja.FullName }
}
if (-not $ninjaExecutable) { throw "Ninja is required; install it or an Android SDK CMake package" }

# Per-ABI toolchain mappings.
$VcpkgTriplets = @{
    "arm64-v8a" = "arm64-android"
    "x86_64"    = "x64-android"
}
$SkiaCpus = @{
    "arm64-v8a" = "arm64"
    "x86_64"    = "x86_64"
}
$ClangTargets = @{
    "arm64-v8a" = "aarch64-linux-android"
    "x86_64"    = "x86_64-linux-android"
}
$FilamentArchs = @{
    "arm64-v8a" = "arm64-v8a"
    "x86_64"    = "x86_64"
}

foreach ($abi in $Abis) {
    if (-not $VcpkgTriplets.ContainsKey($abi)) {
        throw "Unsupported Android ABI '$abi'. Supported: $($VcpkgTriplets.Keys -join ', ')"
    }
}

# ---- vcpkg: install every required triplet into one install root ----
$vcpkgCommand = Get-Command vcpkg -ErrorAction SilentlyContinue
$vcpkgExecutable = if ($null -ne $vcpkgCommand) { $vcpkgCommand.Source } else { "" }
foreach ($vcpkgRoot in @($env:VCPKG_INSTALLATION_ROOT, "C:\vcpkg")) {
    if ($vcpkgExecutable -or -not $vcpkgRoot) { continue }
    $vcpkgCandidate = Join-Path $vcpkgRoot "vcpkg.exe"
    if (Test-Path -LiteralPath $vcpkgCandidate) {
        $vcpkgExecutable = $vcpkgCandidate
    }
}
if (-not $vcpkgExecutable) {
    throw "vcpkg is required to build the Android OpenSSL and ENet libraries"
}
$vcpkgInstalled = Join-Path $repo "build\vcpkg-installed"
$vcpkgArgs = New-Object System.Collections.ArrayList
foreach ($abi in $Abis) {
    $triplet = $VcpkgTriplets[$abi]
    [void]$vcpkgArgs.Add("openssl:$triplet")
    [void]$vcpkgArgs.Add("enet:$triplet")
}
& $vcpkgExecutable install $vcpkgArgs "--x-install-root=$vcpkgInstalled"
if ($LASTEXITCODE -ne 0) { throw "Android OpenSSL/ENet dependency build failed" }

$filamentVersion = "1.74.0"
$sdlVersion = "3.4.14"
$cache = Join-Path $repo ".cache\android"
$filamentRoot = Join-Path $cache "filament\filament"
$filamentHostRoot = Join-Path $cache "filament-host"
$localFilamentHost = Join-Path $repo "vendor\build\_deps\filament_prebuilt-src"
if (Test-Path (Join-Path $localFilamentHost "bin\matc.exe")) {
    $filamentHostRoot = $localFilamentHost
}
$sdlAar = Join-Path $cache "sdl3\SDL3-$sdlVersion.aar"
$skiaRoot = Join-Path $repo "vendor\build\vendor\kine_skia\skia-src"
$box2dRoot = Join-Path $cache "box2d"

function Expand-Tarball([string]$Url, [string]$Archive, [string]$Destination) {
    New-Item -ItemType Directory -Force $Destination | Out-Null
    if (-not (Test-Path $Archive)) {
        & curl.exe --fail --location --retry 4 --output $Archive $Url
        if ($LASTEXITCODE -ne 0) { throw "Could not download $Url" }
    }
    & tar -xf $Archive -C $Destination
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $Archive" }
}

# ---- Filament: one native bundle typically ships every ABI ----
foreach ($abi in $Abis) {
    $filamentArch = $FilamentArchs[$abi]
    $filamentLib = Join-Path $filamentRoot "lib\$filamentArch\libfilament.a"
    if (-not (Test-Path $filamentLib)) {
        $archive = Join-Path $cache "filament\filament-v$filamentVersion-android-native.tgz"
        Expand-Tarball "https://github.com/google/filament/releases/download/v$filamentVersion/filament-v$filamentVersion-android-native.tgz" $archive (Split-Path $filamentRoot)
        break
    }
}
if (-not (Test-Path (Join-Path $filamentHostRoot "bin\matc.exe"))) {
    $archive = Join-Path $cache "filament-host\filament-v$filamentVersion-windows.tgz"
    Expand-Tarball "https://github.com/google/filament/releases/download/v$filamentVersion/filament-v$filamentVersion-windows.tgz" $archive $filamentHostRoot
}
foreach ($hostTool in @('matc.exe', 'resgen.exe')) {
    if (-not (Test-Path (Join-Path $filamentHostRoot "bin\$hostTool"))) {
        throw "Filament host tool $hostTool was not found under $filamentHostRoot"
    }
}
if (-not (Test-Path $sdlAar)) {
    $sdlDir = Split-Path $sdlAar
    $archive = Join-Path $sdlDir "SDL3-devel-$sdlVersion-android.zip"
    New-Item -ItemType Directory -Force $sdlDir | Out-Null
    if (-not (Test-Path $archive)) {
        & curl.exe --fail --location --retry 4 --output $archive "https://github.com/libsdl-org/SDL/releases/download/release-$sdlVersion/SDL3-devel-$sdlVersion-android.zip"
        if ($LASTEXITCODE -ne 0) { throw "SDL3 Android download failed" }
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $sdlDir -Force
}
if (-not $UsePrebuiltSkia -and -not (Test-Path (Join-Path $skiaRoot "bin\gn.exe"))) {
    throw "The Skia checkout is missing at $skiaRoot. Run the desktop dependency build once, then retry."
}
if (-not (Test-Path (Join-Path $box2dRoot ".git"))) {
    New-Item -ItemType Directory -Force (Split-Path $box2dRoot) | Out-Null
    & git clone --depth 1 --branch v3.1.1 https://github.com/erincatto/box2d.git $box2dRoot
    if ($LASTEXITCODE -ne 0) { throw "Box2D checkout failed" }
}

if ($PrepareOnly) {
    Write-Host 'Android dependency packages are ready'
    return
}

# ---- Python shim for Skia GN/Ninja (ABI-agnostic, run once) ----
$oldPath = $env:PATH
if (-not $UsePrebuiltSkia) {
$pythonExecutable = ""
foreach ($pythonName in @("python", "python3")) {
    $pythonCommand = Get-Command $pythonName -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) { continue }
    $probe = & $pythonCommand.Source -c "import sys; print(sys.executable)" 2>$null
    if ($LASTEXITCODE -eq 0 -and $probe) {
        $pythonExecutable = $probe.Trim()
        break
    }
}
if (-not $pythonExecutable) {
    $pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $pythonLauncher) {
        $probe = & $pythonLauncher.Source -3 -c "import sys; print(sys.executable)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $probe) { $pythonExecutable = $probe.Trim() }
    }
}
if (-not $pythonExecutable) { throw "A working Python 3 interpreter is required to build Skia" }
$pythonShimBase = $env:USERPROFILE
if (-not $pythonShimBase -or [IO.Path]::GetPathRoot($pythonShimBase) -ne [IO.Path]::GetPathRoot($pythonExecutable)) {
    $pythonShimBase = Split-Path $pythonExecutable
}
$pythonShim = Join-Path $pythonShimBase ".kinemium\android-python"
New-Item -ItemType Directory -Force $pythonShim | Out-Null
$pythonShimExecutable = Join-Path $pythonShim "python3.exe"
if (Test-Path -LiteralPath $pythonShimExecutable) {
    Remove-Item -LiteralPath $pythonShimExecutable -Force
}
    New-Item -ItemType HardLink -Path $pythonShimExecutable -Target $pythonExecutable | Out-Null
$env:PATH = "$pythonShim;$(Split-Path $pythonExecutable);$oldPath"
}

# ---- Per-ABI builds ----
$toolchain = Join-Path $ndk "build\cmake\android.toolchain.cmake"

foreach ($abi in $Abis) {
    $skiaCpu = $SkiaCpus[$abi]
    $clangTarget = $ClangTargets[$abi]
    $filamentArch = $FilamentArchs[$abi]
    $skiaBuildName = "KinemiumAndroid-$abi"
    $skiaCmakeArgs = @()
    if ($UsePrebuiltSkia) {
        $prebuiltArch = if ($abi -eq "arm64-v8a") { "arm64" } else { "x64" }
        $skiaRoot = Join-Path $repo ".cache\skia\android-$prebuiltArch"
        $skiaBuildName = "Release-$prebuiltArch"
        $skiaConfig = Join-Path $skiaRoot "skia.cmake"
        if (-not (Test-Path -LiteralPath $skiaConfig)) {
            throw "Missing Skia binary: run python tools/fetch_skia.py --platform android --arch $prebuiltArch"
        }
        $skiaCmakeArgs = @('-C', $skiaConfig)
    }
    $skiaOut = Join-Path $skiaRoot "out\$skiaBuildName"
    $nativeBuild = Join-Path $repo "build\android-native-$abi"
    $boxBuild = Join-Path $repo "build\android-box2d-$abi"
    $vendorOut = Join-Path $repo "build\android-vendor-$abi"
    $jniOut = Join-Path $repo "build\android-jni\$abi"
    $odinObjects = Join-Path $repo "build\android-$abi"

    Write-Host "=== Building Android $abi ==="

    # ---- Skia (per ABI) ----
    $skiaArgsFile = Join-Path $skiaOut "args.gn"
    $skiaNeedsBuild = $true
    if ((Test-Path (Join-Path $skiaOut "libsvg.a")) -and (Test-Path $skiaArgsFile) -and (Select-String -Path $skiaArgsFile -Pattern 'skia_use_gl\s*=\s*true' -Quiet)) {
        $skiaNeedsBuild = $false
    }
    if (-not $UsePrebuiltSkia -and $skiaNeedsBuild) {
        $gnArgs = 'target_os="android" target_cpu="' + $skiaCpu + '" ndk="' + ($ndk -replace '\\','/') + '" is_debug=false is_official_build=true is_component_build=false skia_enable_ganesh=true skia_enable_svg=true skia_enable_skshaper=true skia_use_vulkan=false skia_use_gl=true skia_gl_standard="gles" skia_use_expat=true skia_use_system_expat=false skia_use_harfbuzz=true skia_use_system_harfbuzz=false skia_use_icu=true skia_use_system_icu=false skia_use_freetype=true skia_use_system_freetype2=false skia_use_libpng_decode=true skia_use_libpng_encode=true skia_use_system_libpng=false skia_use_system_libjpeg_turbo=false skia_use_system_libwebp=false skia_use_system_zlib=false skia_use_dng_sdk=false'
        Push-Location $skiaRoot
        try {
            & .\bin\gn.exe gen $skiaOut "--args=$gnArgs"
            if ($LASTEXITCODE -ne 0) { throw "Skia Android $abi configuration failed" }
            & $ninjaExecutable -C $skiaOut skia svg skshaper skunicode_core skunicode_icu
            if ($LASTEXITCODE -ne 0) { throw "Skia Android $abi build failed" }
        } finally { Pop-Location }
    }

    # ---- CMake native dependencies (per ABI) ----
    & cmake -S (Join-Path $repo "cmake\android-native") -B $nativeBuild -G Ninja @skiaCmakeArgs "-DCMAKE_MAKE_PROGRAM=$ninjaExecutable" "-DCMAKE_TOOLCHAIN_FILE=$toolchain" "-DANDROID_ABI=$abi" "-DANDROID_PLATFORM=android-$ApiLevel" -DANDROID_STL=c++_static "-DFILAMENT_DIR=$filamentRoot" "-DFILAMENT_LIB_ARCH=$filamentArch" "-DKINE_SKIA_DIR=$skiaRoot" "-DKINE_SKIA_BUILD_NAME=$skiaBuildName" "-DFILAMENT_HOST_TOOLS_DIR=$(Join-Path $filamentHostRoot 'bin')" "-DKINE_ANDROID_VCPKG_DIR=$(Join-Path $vcpkgInstalled $VcpkgTriplets[$abi])" "-DKINE_ANDROID_JNI_DIR=$jniOut" "-DKINE_ANDROID_VENDOR_DIR=$vendorOut" -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw "Native Android $abi configuration failed" }
    & cmake --build $nativeBuild --parallel
    if ($LASTEXITCODE -ne 0) { throw "Native Android $abi dependency build failed" }

    $boxBuild = Join-Path $repo "build\android-box2d-$abi"
    & cmake -S $box2dRoot -B $boxBuild -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninjaExecutable" "-DCMAKE_TOOLCHAIN_FILE=$toolchain" "-DANDROID_ABI=$abi" "-DANDROID_PLATFORM=android-$ApiLevel" -DANDROID_STL=c++_static -DBOX2D_SAMPLES=OFF -DBOX2D_UNIT_TESTS=OFF -DBOX2D_VALIDATE=OFF -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw "Box2D Android $abi configuration failed" }
    & cmake --build $boxBuild --parallel
    if ($LASTEXITCODE -ne 0) { throw "Box2D Android $abi build failed" }

    # ---- Odin vendor static libs (per ABI) ----
    $clang = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\$clangTarget$ApiLevel-clang.cmd"
    $ar = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-ar.exe"
    New-Item -ItemType Directory -Force $vendorOut | Out-Null
    & $clang -O3 -fPIC -c (Join-Path $odinRoot "vendor\miniaudio\src\miniaudio.c") -o (Join-Path $vendorOut "miniaudio.o")
    if ($LASTEXITCODE -ne 0) { throw "miniaudio Android $abi compilation failed" }
    & $ar rcs (Join-Path $vendorOut "miniaudio.a") (Join-Path $vendorOut "miniaudio.o")
    if ($LASTEXITCODE -ne 0) { throw "miniaudio Android $abi archive failed" }
    foreach ($name in @("stb_image", "stb_image_resize2", "stb_image_write")) {
        & $clang -O3 -fPIC -c (Join-Path $odinRoot "vendor\stb\src\$name.c") -o (Join-Path $vendorOut "$name.o")
        if ($LASTEXITCODE -ne 0) { throw "$name Android $abi compilation failed" }
        & $ar rcs (Join-Path $vendorOut "$name.a") (Join-Path $vendorOut "$name.o")
        if ($LASTEXITCODE -ne 0) { throw "$name Android $abi archive failed" }
    }
    New-Item -ItemType Directory -Force (Join-Path $odinRoot "vendor\miniaudio\lib\android\$abi") | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $odinRoot "vendor\miniaudio\lib\$abi") | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $odinRoot "vendor\stb\lib\$abi") | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $odinRoot "vendor\box2d\lib\$abi") | Out-Null
    Copy-Item (Join-Path $vendorOut "miniaudio.a") (Join-Path $odinRoot "vendor\miniaudio\lib\android\$abi\miniaudio.a") -Force
    Copy-Item (Join-Path $vendorOut "miniaudio.a") (Join-Path $odinRoot "vendor\miniaudio\lib\$abi\miniaudio.a") -Force
    Copy-Item (Join-Path $vendorOut "miniaudio.a") (Join-Path $odinRoot "vendor\miniaudio\lib\miniaudio.a") -Force
    foreach ($name in @("stb_image", "stb_image_resize2", "stb_image_write")) {
        Copy-Item (Join-Path $vendorOut "$name.a") (Join-Path $odinRoot "vendor\stb\lib\$abi\$name.a") -Force
        Copy-Item (Join-Path $vendorOut "$name.a") (Join-Path $odinRoot "vendor\stb\lib\$name.a") -Force
    }
    Copy-Item (Join-Path $boxBuild "src\libbox2d.a") (Join-Path $odinRoot "vendor\box2d\lib\$abi\box2d_other.a") -Force
    Copy-Item (Join-Path $boxBuild "src\libbox2d.a") (Join-Path $odinRoot "vendor\box2d\lib\box2d_other.a") -Force
    if ($abi -eq "x86_64") {
        Copy-Item (Join-Path $boxBuild "src\libbox2d.a") (Join-Path $odinRoot "vendor\box2d\lib\box2d_other_amd64.a") -Force
        Copy-Item (Join-Path $boxBuild "src\libbox2d.a") (Join-Path $odinRoot "vendor\box2d\lib\box2d_other_amd64_sse2.a") -Force
    }

    # ---- Odin compilation (per ABI target) ----
    $odinTarget = if ($abi -eq "arm64-v8a") { "linux_arm64" } else { "linux_amd64" }
    New-Item -ItemType Directory -Force $odinObjects | Out-Null
    Get-ChildItem -LiteralPath $odinObjects -Filter "kinemium-*.o" -File -ErrorAction SilentlyContinue | Remove-Item -Force
    $env:ODIN_ANDROID_NDK = $ndk
    & odin check (Join-Path $repo "src") -target:$odinTarget -subtarget:android -define:KINE_ANDROID=true -define:KINE_RENDERER_GL=true
    if ($LASTEXITCODE -ne 0) { throw "Odin Android $abi source check failed" }
    & odin build (Join-Path $repo "src") -target:$odinTarget -subtarget:android "-minimum-os-version:$ApiLevel" -build-mode:obj "-out:$odinObjects\kinemium.o" -define:KINE_ANDROID=true -define:KINE_RENDERER_GL=true
    if ($LASTEXITCODE -ne 0) { throw "Odin Android $abi compilation failed" }

    # ---- Link libmain.so (per ABI) ----
    & cmake -S (Join-Path $repo "cmake\android-native") -B $nativeBuild "-DFILAMENT_HOST_TOOLS_DIR=$(Join-Path $filamentHostRoot 'bin')" "-DKINE_ODIN_OBJECT_DIR=$odinObjects" "-DKINE_ANDROID_BOX2D_LIBRARY=$boxBuild/src/libbox2d.a"
    if ($LASTEXITCODE -ne 0) { throw "Android $abi link configuration failed" }
    & cmake --build $nativeBuild --target kinemium_android --parallel
    if ($LASTEXITCODE -ne 0) { throw "libmain.so link failed for $abi" }
}

$env:PATH = $oldPath

# ---- Package APK with every requested ABI ----
$env:ANDROID_HOME = $AndroidSdk
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr" }
& (Join-Path $repo "android\gradlew.bat") --no-daemon -p (Join-Path $repo "android") :app:assembleDebug "-PandroidAbiFilters=$($Abis -join ',')"
if ($LASTEXITCODE -ne 0) { throw "APK packaging failed" }

$apk = Join-Path $repo "android\app\build\outputs\apk\debug\app-debug.apk"
Write-Host "Android APK: $apk"

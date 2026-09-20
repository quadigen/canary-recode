param(
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$NdkVersion = "30.0.16248370",
    [int]$ApiLevel = 28
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $AndroidSdk) { $AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$ndk = Join-Path $AndroidSdk "ndk\$NdkVersion"
if (-not (Test-Path (Join-Path $ndk "build\cmake\android.toolchain.cmake"))) {
    throw "Android NDK $NdkVersion was not found under $AndroidSdk"
}

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
$skiaOut = Join-Path $skiaRoot "out\KinemiumAndroid"
$box2dRoot = Join-Path $cache "box2d"

function Expand-Tarball([string]$Url, [string]$Archive, [string]$Destination) {
    New-Item -ItemType Directory -Force $Destination | Out-Null
    if (-not (Test-Path $Archive)) { Invoke-WebRequest $Url -OutFile $Archive }
    & tar -xf $Archive -C $Destination
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $Archive" }
}

if (-not (Test-Path (Join-Path $filamentRoot "lib\arm64-v8a\libfilament.a"))) {
    $archive = Join-Path $cache "filament\filament-v$filamentVersion-android-native.tgz"
    Expand-Tarball "https://github.com/google/filament/releases/download/v$filamentVersion/filament-v$filamentVersion-android-native.tgz" $archive (Split-Path $filamentRoot)
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
        Invoke-WebRequest "https://github.com/libsdl-org/SDL/releases/download/release-$sdlVersion/SDL3-devel-$sdlVersion-android.zip" -OutFile $archive
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $sdlDir -Force
}
if (-not (Test-Path (Join-Path $skiaRoot "bin\gn.exe"))) {
    throw "The Skia checkout is missing at $skiaRoot. Run the desktop dependency build once, then retry."
}
if (-not (Test-Path (Join-Path $box2dRoot ".git"))) {
    New-Item -ItemType Directory -Force (Split-Path $box2dRoot) | Out-Null
    & git clone --depth 1 --branch v3.1.1 https://github.com/erincatto/box2d.git $box2dRoot
    if ($LASTEXITCODE -ne 0) { throw "Box2D checkout failed" }
}

$oldPath = $env:PATH
$pythonDir = Split-Path (Get-Command python).Source
$env:PATH = "$pythonDir;$oldPath"
if (-not (Test-Path (Join-Path $skiaOut "libsvg.a"))) {
    $gnArgs = 'target_os="android" target_cpu="arm64" ndk="' + ($ndk -replace '\\','/') + '" is_debug=false is_official_build=true is_component_build=false skia_enable_ganesh=true skia_enable_svg=true skia_enable_skshaper=true skia_use_vulkan=true skia_use_gl=false skia_use_expat=true skia_use_system_expat=false skia_use_harfbuzz=true skia_use_system_harfbuzz=false skia_use_icu=true skia_use_system_icu=false skia_use_freetype=true skia_use_system_freetype2=false skia_use_libpng_decode=true skia_use_libpng_encode=true skia_use_system_libpng=false skia_use_system_libjpeg_turbo=false skia_use_system_libwebp=false skia_use_system_zlib=false skia_use_dng_sdk=false'
    Push-Location $skiaRoot
    try {
        & .\bin\gn.exe gen out/KinemiumAndroid "--args=$gnArgs"
    & ninja -C out/KinemiumAndroid skia svg skshaper skunicode_core skunicode_icu
        if ($LASTEXITCODE -ne 0) { throw "Skia Android build failed" }
    } finally { Pop-Location }
}
$env:PATH = $oldPath

$toolchain = Join-Path $ndk "build\cmake\android.toolchain.cmake"
$nativeBuild = Join-Path $repo "build\android-native"
& cmake -S (Join-Path $repo "cmake\android-native") -B $nativeBuild -G Ninja "-DCMAKE_TOOLCHAIN_FILE=$toolchain" -DANDROID_ABI=arm64-v8a "-DANDROID_PLATFORM=android-$ApiLevel" -DANDROID_STL=c++_static "-DFILAMENT_DIR=$filamentRoot" "-DKINE_SKIA_DIR=$skiaRoot" "-DFILAMENT_HOST_TOOLS_DIR=$(Join-Path $filamentHostRoot 'bin')" -DCMAKE_BUILD_TYPE=Release
& cmake --build $nativeBuild --parallel
if ($LASTEXITCODE -ne 0) { throw "Native Android dependency build failed" }

$boxBuild = Join-Path $repo "build\android-box2d"
& cmake -S $box2dRoot -B $boxBuild -G Ninja "-DCMAKE_TOOLCHAIN_FILE=$toolchain" -DANDROID_ABI=arm64-v8a "-DANDROID_PLATFORM=android-$ApiLevel" -DANDROID_STL=c++_static -DBOX2D_SAMPLES=OFF -DBOX2D_UNIT_TESTS=OFF -DBOX2D_VALIDATE=OFF -DCMAKE_BUILD_TYPE=Release
& cmake --build $boxBuild --parallel
if ($LASTEXITCODE -ne 0) { throw "Box2D Android build failed" }

$odinRoot = Split-Path (Get-Command odin).Source
$clang = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android$ApiLevel-clang.cmd"
$ar = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-ar.exe"
$vendorOut = Join-Path $repo "build\android-vendor"
New-Item -ItemType Directory -Force $vendorOut | Out-Null
& $clang -O3 -fPIC -c (Join-Path $odinRoot "vendor\miniaudio\src\miniaudio.c") -o (Join-Path $vendorOut "miniaudio.o")
& $ar rcs (Join-Path $vendorOut "miniaudio.a") (Join-Path $vendorOut "miniaudio.o")
foreach ($name in @("stb_image", "stb_image_resize", "stb_image_write")) {
    & $clang -O3 -fPIC -c (Join-Path $odinRoot "vendor\stb\src\$name.c") -o (Join-Path $vendorOut "$name.o")
    & $ar rcs (Join-Path $vendorOut "$name.a") (Join-Path $vendorOut "$name.o")
    Copy-Item (Join-Path $vendorOut "$name.a") (Join-Path $odinRoot "vendor\stb\lib\$name.a") -Force
}
Copy-Item (Join-Path $vendorOut "miniaudio.a") (Join-Path $odinRoot "vendor\miniaudio\lib\miniaudio.a") -Force
Copy-Item (Join-Path $boxBuild "src\libbox2d.a") (Join-Path $odinRoot "vendor\box2d\lib\box2d_other.a") -Force

$odinObjects = Join-Path $repo "build\android"
New-Item -ItemType Directory -Force $odinObjects | Out-Null
Get-ChildItem -LiteralPath $odinObjects -Filter "kinemium-*.o" -File -ErrorAction SilentlyContinue | Remove-Item -Force
$env:ODIN_ANDROID_NDK = $ndk
& odin check (Join-Path $repo "src") -target:linux_arm64 -subtarget:android -define:KINE_ANDROID=true
& odin build (Join-Path $repo "src") -target:linux_arm64 -subtarget:android "-minimum-os-version:$ApiLevel" -build-mode:obj "-out:$odinObjects\kinemium.o" -define:KINE_ANDROID=true
if ($LASTEXITCODE -ne 0) { throw "Odin Android compilation failed" }

& cmake -S (Join-Path $repo "cmake\android-native") -B $nativeBuild "-DFILAMENT_HOST_TOOLS_DIR=$(Join-Path $filamentHostRoot 'bin')"
& cmake --build $nativeBuild --target kinemium_android --parallel
if ($LASTEXITCODE -ne 0) { throw "libmain.so link failed" }

$env:ANDROID_HOME = $AndroidSdk
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr" }
& (Join-Path $repo "android\gradlew.bat") --no-daemon -p (Join-Path $repo "android") :app:assembleDebug
if ($LASTEXITCODE -ne 0) { throw "APK packaging failed" }

$apk = Join-Path $repo "android\app\build\outputs\apk\debug\app-debug.apk"
Write-Host "Android APK: $apk"

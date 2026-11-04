# justfile

set shell := ["powershell.exe", "-NoProfile", "-Command"]

git_commit := `git rev-parse --short HEAD`
git_branch := `git rev-parse --abbrev-ref HEAD`

version := "1.19.2"

default:
    @just --list

build:
    odin build src -o:speed -out:build/kinemium.exe

debug:
    odin build src -debug -out:build/kinemium-debug.exe -extra-linker-flags:"/LTCG /IGNORE:4099" -define:TRACY_ENABLE=true

release:
    @Get-Process kinemium -ErrorAction SilentlyContinue | Stop-Process -Force
    odin build src -o:speed -out:build/kinemium.exe -define:BUILD_TARGET=editor -define:RUNTIME_VERSION_DISPLAY={{version}} -define:RUNTIME_GIT_ENABLED=true -define:RUNTIME_GIT_COMMIT={{git_commit}} -define:RUNTIME_GIT_BRANCH={{git_branch}}

wasm:
    & ./tools/build_wasm.ps1

wasm-serve:
    python -m http.server 8000 --directory build/web

wasm-client address="" port="":
    & ./tools/build_wasm_client.ps1 -Address "{{address}}" -Port "{{port}}"

wasm-client-serve:
    python -m http.server 8001 --directory build/web-client

android:
    & ./tools/build_android.ps1

run: build
    ./build/kinemium.exe

run-debug: debug
    ./build/kinemium-debug.exe

run-sandbox script="C:\\Users\\devco\\Documents\\Kinemium-Canary\\src\\sandboxed\\internals\\gui\\mainframe.luau": debug
    ./build/kinemium-debug.exe --script "{{script}}"

test:
    odin test src
    odin test src/engine/assetstore
    @just test-serializer
    @just test-replication
    @just test-services
    @just test-gui

test-services:
    #!pwsh
    $ErrorActionPreference = 'Stop'
    $tests = @(
        'jolt_bindings_smoke',
        'jolt_threading_smoke',
        'part_teardown_smoke',
        'part_body_churn_smoke',
        'part_nil_body_smoke',
        'physics_sleep_tuning_smoke',
        'physics_collider_smoke',
        'workspace_physics_smoke',
        'hinge_constraint_smoke',
        'luau_typecheck_smoke',
        'constraint_car_turn_smoke',
        'character_controller_smoke',
        'character_cancollide_smoke',
        'terrain_character_ground_smoke',
        'terrain_surface_jump_smoke',
        'character_push_smoke',
        'mouse_smoke',
        'highlight_smoke',
        'handles_smoke',
        'lighting_smoke',
        'material_catalog_smoke',
        'water_buoyancy_camera_smoke',
        'terrain_service_smoke',
        'terrain_collision_smoke',
        'singleplayer_smoke',
        'playtest_launch_smoke',
        'webview_service_smoke',
        'template_platform_smoke',
        'platform_export_smoke',
        'filesystem_copy_smoke',
        'datastore_smoke',
        'plugin_api_smoke',
        'marketplace_plugin_smoke'
    )
    $failed = @()
    foreach ($t in $tests) {
        $output = (odin run "tests/$t.odin" -file 2>&1 | Out-String)
        if ($output -match 'PASSED') {
            Write-Host "PASS  $t"
        } else {
            Write-Host "FAIL  $t"
            Write-Host $output
            $failed += $t
        }
    }
    if ($failed.Count -gt 0) {
        throw "service tests failed: $($failed -join ', ')"
    }

test-gui:
    #!pwsh
    $ErrorActionPreference = 'Stop'
    $tests = @(
        'gif_image_smoke',
        'gui_component_smoke',
        'viewport_frame_smoke',
        'gui_hit_smoke',
        'gui_hit_test_smoke',
        'gui_rotation_smoke',
        'gui_layout_smoke',
        'screen_gui_clip_smoke',
        'surface_gui_input_smoke'
    )
    $failed = @()
    foreach ($t in $tests) {
        $output = (odin run "tests/$t.odin" -file 2>&1 | Out-String)
        if ($output -match 'PASSED') {
            Write-Host "PASS  $t"
        } else {
            Write-Host "FAIL  $t"
            Write-Host $output
            $failed += $t
        }
    }
    if ($failed.Count -gt 0) {
        throw "gui tests failed: $($failed -join ', ')"
    }

# Usage: just bench-surface-gui [elements] [frames]
bench-surface-gui elements="1000" frames="120":
    odin run tests/surface_gui_bench.odin -file -- {{elements}} {{frames}}

test-serializer:
    #!pwsh
    $ErrorActionPreference = 'Stop'
    $tests = @(
        'serializer_smoke',
        'asset_portability_smoke',
        'kine_map_smoke',
        'kine_terrain_smoke',
    )
    $failed = @()
    foreach ($t in $tests) {
        $output = (odin run "tests/$t.odin" -file 2>&1 | Out-String)
        if ($output -match 'PASSED') {
            Write-Host "PASS  $t"
        } else {
            Write-Host "FAIL  $t"
            Write-Host $output
            $failed += $t
        }
    }
    if ($failed.Count -gt 0) {
        throw "serializer tests failed: $($failed -join ', ')"
    }

test-replication:
    #!pwsh
    $ErrorActionPreference = 'Stop'
    $tests = @(
        'replicator_loopback_smoke',
        'replication_constraint_smoke',
        'replicator_multi_peer_smoke',
        'replication_remote_smoke',
        'replication_breadth_smoke',
        'character_replication_smoke',
        'editor_pivot_smoke',
        'water_character_network_smoke',
        'character_void_world_drive_smoke',
        'character_jump_smoke',
        'character_finished_replicating_smoke',
        'workspace_finished_replicating_smoke',
        'ownership_api_smoke',
        'ownership_events_smoke',
        'vehicle_ownership_smoke',
        'ownership_stress_smoke',
        'replication_ack_suppression_smoke',
        'replication_authority_smoke',
         'replication_handshake_smoke',
         'replication_load_control_smoke',
         'replication_spawn_priority_smoke',
         'replication_timebase_smoke',
         'replication_cadence_smoke',
         'replication_relevancy_smoke',
         'replication_asset_smoke',
         'replication_terrain_smoke',
         'terrain_character_ground_smoke',
        'terrain_surface_jump_smoke',
         'character_death_smoke',
         'character_cancollide_smoke',
         'character_push_smoke',
         'character_push_network_smoke',
         'character_remote_collision_smoke',
         'character_owned_rest_smoke',
         'player_impulse_smoke',
         'part_velocity_smoke'
    )
    $failed = @()
    foreach ($t in $tests) {
        $output = (odin run "tests/$t.odin" -file 2>&1 | Out-String)
        if ($output -match 'PASSED') {
            Write-Host "PASS  $t"
        } else {
            Write-Host "FAIL  $t"
            Write-Host $output
            $failed += $t
        }
    }
    if ($failed.Count -gt 0) {
        throw "replication tests failed: $($failed -join ', ')"
    }

check:
    odin check src

wire:
    @powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/wire_engine.ps1 -RootPath .
    @odin check src

wire-check:
    @powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/wire_engine.ps1 -RootPath . -Check

editor:
    odin build src -define:BUILD_TARGET=editor -out:build/kinemium-editor.exe

client:
    odin build src -define:BUILD_TARGET=client -out:build/kinemium-client.exe

player: client

server:
    odin build src -define:BUILD_TARGET=server -out:build/kinemium-server.exe

release-templates:
    New-Item -ItemType Directory -Force rel | Out-Null
    copy build\kinemium-server.exe rel\kinemium-server-windows-x86_64.exe
    copy build\kinemium-client.exe rel\kinemium-client-windows-x86_64.exe

server-bake map address="0.0.0.0" port="1234":
    odin build src -define:BUILD_TARGET=server -define:KINE_MODE=server -define:KINE_ADDRESS={{address}} -define:KINE_PORT={{port}} -define:KINE_EMBED="$(Resolve-Path '{{map}}')" -out:build/kinemium-server.exe

client-bake address="" map="" port="1234":
    odin build src -define:BUILD_TARGET=client -define:KINE_MODE=client {{ if address != "" { "-define:KINE_ADDRESS=" + address + " " } else { "" } }}-define:KINE_PORT={{port}} {{ if map != "" { "-define:KINE_EMBED=\"$(Resolve-Path '" + map + "')\" " } else { "" } }}-out:build/kinemium-client.exe

custom startup target="client" noedit="false":
    odin build src -define:BUILD_TARGET={{target}} -define:LUAU_STARTUP="$(Resolve-Path '{{startup}}')" -define:NOEDITOR={{noedit}} -out:build/kinemium-custom.exe

run-editor:
    odin run src -define:BUILD_TARGET=editor

playtest map: editor
    ./build/kinemium-editor.exe "{{map}}"

run-client:
    odin run src -define:BUILD_TARGET=client

run-player: run-client

run-server:
    odin run src -define:BUILD_TARGET=server

fmt:
    odinfmt -w src

clean:
    if (Test-Path build) { Remove-Item -Recurse -Force build }
    New-Item -ItemType Directory -Force build | Out-Null

rebuild: clean build

deps:
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

deps-rebuild:
    if (Test-Path vendor/build) { Remove-Item -Recurse -Force vendor/build }
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

all: deps build

kne-example:
    New-Item -ItemType Directory -Force build/kne-extensions/hello_kne | Out-Null
    odin build include/sdk/examples/odin -build-mode:dll -out:build/kne-extensions/hello_kne/hello_kne.dll
    Copy-Item include/sdk/examples/odin/extension.json build/kne-extensions/hello_kne/extension.json -Force

kne-test: kne-example
    odin run tests/kne_extension_smoke.odin -file

# justfile (Windows + Linux)

# Windows uses PowerShell; Linux/macOS use just's default (sh).
set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]

git_commit := `git rev-parse --short HEAD`
git_branch := `git rev-parse --abbrev-ref HEAD`

version := "1.19.2"

# ---------------------------------------------------------------------------
# Platform helpers
# ---------------------------------------------------------------------------

exe     := if os() == "windows" { ".exe" } else { "" }
dll_ext := if os() == "windows" { "dll" } else { "so" }
python  := if os() == "windows" { "python" } else { "python3" }
resolve := if os() == "windows" { "Resolve-Path" } else { "realpath" }

# MSVC-only linker flags; not applicable on Linux
debug_linker := if os() == "windows" { '-extra-linker-flags:"/LTCG /IGNORE:4099"' } else { "" }

default:
    @just --list

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build:
    odin build src -o:speed -out:build/kinemium{{exe}}

debug:
    odin build src -debug -out:build/kinemium-debug{{exe}} {{debug_linker}} -define:TRACY_ENABLE=true

[windows]
_kill:
    @Get-Process kinemium -ErrorAction SilentlyContinue | Stop-Process -Force

[unix]
_kill:
    @pkill -x kinemium || true

release: _kill
    odin build src -o:speed -out:build/kinemium{{exe}} -define:BUILD_TARGET=editor -define:RUNTIME_VERSION_DISPLAY={{version}} -define:RUNTIME_GIT_ENABLED=true -define:RUNTIME_GIT_COMMIT={{git_commit}} -define:RUNTIME_GIT_BRANCH={{git_branch}}

# ---------------------------------------------------------------------------
# WASM / Android
# (the tools/*.ps1 scripts run via PowerShell 7 `pwsh` on Linux)
# ---------------------------------------------------------------------------

[windows]
wasm:
    & ./tools/build_wasm.ps1

[unix]
wasm:
    pwsh -NoProfile -File ./tools/build_wasm.ps1

wasm-serve:
    {{python}} -m http.server 8000 --directory build/web

[windows]
wasm-client address="" port="":
    & ./tools/build_wasm_client.ps1 -Address "{{address}}" -Port "{{port}}"

[unix]
wasm-client address="" port="":
    pwsh -NoProfile -File ./tools/build_wasm_client.ps1 -Address "{{address}}" -Port "{{port}}"

wasm-client-serve:
    {{python}} -m http.server 8001 --directory build/web-client

[windows]
android:
    & ./tools/build_android.ps1

[unix]
android:
    pwsh -NoProfile -File ./tools/build_android.ps1

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

run: build
    ./build/kinemium{{exe}}

run-debug: debug
    ./build/kinemium-debug{{exe}}

run-sandbox script="src/sandboxed/internals/gui/mainframe.luau": debug
    ./build/kinemium-debug{{exe}} --script "{{script}}"

# ---------------------------------------------------------------------------
# Tests
# Test lists are whitespace-separated so the same list feeds both runners.
# ---------------------------------------------------------------------------

tests_services := '''
    jolt_bindings_smoke
    jolt_threading_smoke
    part_teardown_smoke
    part_body_churn_smoke
    part_nil_body_smoke
    physics_sleep_tuning_smoke
    physics_collider_smoke
    workspace_physics_smoke
    hinge_constraint_smoke
    spring_constraint_smoke
    luau_typecheck_smoke
    constraint_car_turn_smoke
    character_controller_smoke
    character_cancollide_smoke
    cloth_collision_smoke
    softbody_smoke
    softbody_collision_smoke
    terrain_character_ground_smoke
    terrain_surface_jump_smoke
    character_push_smoke
    mouse_smoke
    highlight_smoke
    handles_smoke
    lighting_smoke
    material_catalog_smoke
    water_buoyancy_camera_smoke
    terrain_service_smoke
    terrain_collision_smoke
    singleplayer_smoke
    playtest_launch_smoke
    webview_service_smoke
    template_platform_smoke
    platform_export_smoke
    filesystem_copy_smoke
    datastore_smoke
    plugin_api_smoke
    marketplace_plugin_smoke
'''

tests_gui := '''
    gif_image_smoke
    gui_component_smoke
    player_gui_smoke
    ui_shader_smoke
    viewport_frame_smoke
    gui_hit_smoke
    gui_hit_test_smoke
    gui_rotation_smoke
    gui_layout_smoke
    screen_gui_clip_smoke
    surface_gui_input_smoke
'''

tests_serializer := '''
    serializer_smoke
    asset_portability_smoke
    kine_map_smoke
    kine_terrain_smoke
'''

tests_replication := '''
    replicator_loopback_smoke
    replication_constraint_smoke
    replicator_multi_peer_smoke
    replication_remote_smoke
    replication_breadth_smoke
    character_replication_smoke
    editor_pivot_smoke
    water_character_network_smoke
    character_void_world_drive_smoke
    character_jump_smoke
    character_finished_replicating_smoke
    workspace_finished_replicating_smoke
    ownership_api_smoke
    ownership_events_smoke
    vehicle_ownership_smoke
    ownership_stress_smoke
    replication_ack_suppression_smoke
    replication_authority_smoke
    replication_handshake_smoke
    replication_load_control_smoke
    replication_spawn_priority_smoke
    replication_timebase_smoke
    replication_cadence_smoke
    replication_relevancy_smoke
    replication_asset_smoke
    replication_terrain_smoke
    terrain_character_ground_smoke
    terrain_surface_jump_smoke
    character_death_smoke
    character_cancollide_smoke
    character_push_smoke
    character_push_network_smoke
    character_remote_collision_smoke
    character_owned_rest_smoke
    player_impulse_smoke
    part_velocity_smoke
'''

# Shared runner: runs each tests/<name>.odin and checks for PASSED in the output.
[windows]
_run-tests label tests:
    #!pwsh
    $ErrorActionPreference = 'Stop'
    $tests = '{{tests}}' -split '\s+' | Where-Object { $_ }
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
        throw "{{label}} tests failed: $($failed -join ', ')"
    }

[unix]
_run-tests label tests:
    #!/usr/bin/env bash
    set -uo pipefail
    failed=()
    for t in {{tests}}; do
        output=$(odin run "tests/$t.odin" -file 2>&1)
        if grep -q PASSED <<< "$output"; then
            echo "PASS  $t"
        else
            echo "FAIL  $t"
            echo "$output"
            failed+=("$t")
        fi
    done
    if [ ${#failed[@]} -gt 0 ]; then
        echo "{{label}} tests failed: ${failed[*]}" >&2
        exit 1
    fi

test:
    odin test src
    odin test src/engine/assetstore
    @just test-serializer
    @just test-replication
    @just test-services
    @just test-gui

test-services: (_run-tests "service" tests_services)

test-gui: (_run-tests "gui" tests_gui)

test-serializer: (_run-tests "serializer" tests_serializer)

test-replication: (_run-tests "replication" tests_replication)

# Usage: just bench-surface-gui [elements] [frames]
bench-surface-gui elements="1000" frames="120":
    odin run tests/surface_gui_bench.odin -file -- {{elements}} {{frames}}

# ---------------------------------------------------------------------------
# Checks / tooling
# ---------------------------------------------------------------------------

check:
    odin check src

[windows]
wire:
    @powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/wire_engine.ps1 -RootPath .
    @odin check src

[unix]
wire:
    @pwsh -NoProfile -File ./tools/wire_engine.ps1 -RootPath .
    @odin check src

[windows]
wire-check:
    @powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/wire_engine.ps1 -RootPath . -Check

[unix]
wire-check:
    @pwsh -NoProfile -File ./tools/wire_engine.ps1 -RootPath . -Check

fmt:
    odinfmt -w src

# ---------------------------------------------------------------------------
# Editor / client / server targets
# ---------------------------------------------------------------------------

editor:
    odin build src -define:BUILD_TARGET=editor -out:build/kinemium-editor{{exe}}

client:
    odin build src -define:BUILD_TARGET=client -out:build/kinemium-client{{exe}}

player: client

server:
    odin build src -define:BUILD_TARGET=server -out:build/kinemium-server{{exe}}

[windows]
release-templates:
    New-Item -ItemType Directory -Force rel | Out-Null
    copy build\kinemium-server.exe rel\kinemium-server-windows-x86_64.exe
    copy build\kinemium-client.exe rel\kinemium-client-windows-x86_64.exe

[unix]
release-templates:
    mkdir -p rel
    cp build/kinemium-server rel/kinemium-server-{{os()}}-{{arch()}}
    cp build/kinemium-client rel/kinemium-client-{{os()}}-{{arch()}}

server-bake map address="0.0.0.0" port="1234":
    odin build src -define:BUILD_TARGET=server -define:KINE_MODE=server -define:KINE_ADDRESS={{address}} -define:KINE_PORT={{port}} -define:KINE_EMBED="$({{resolve}} '{{map}}')" -out:build/kinemium-server{{exe}}

client-bake address="" map="" port="1234":
    odin build src -define:BUILD_TARGET=client -define:KINE_MODE=client {{ if address != "" { "-define:KINE_ADDRESS=" + address + " " } else { "" } }}-define:KINE_PORT={{port}} {{ if map != "" { "-define:KINE_EMBED=\"$(" + resolve + " '" + map + "')\" " } else { "" } }}-out:build/kinemium-client{{exe}}

custom startup target="client" noedit="false":
    odin build src -define:BUILD_TARGET={{target}} -define:LUAU_STARTUP="$({{resolve}} '{{startup}}')" -define:NOEDITOR={{noedit}} -out:build/kinemium-custom{{exe}}

run-editor:
    odin run src -define:BUILD_TARGET=editor

playtest map: editor
    ./build/kinemium-editor{{exe}} "{{map}}"

run-client:
    odin run src -define:BUILD_TARGET=client

run-player: run-client

run-server:
    odin run src -define:BUILD_TARGET=server

# ---------------------------------------------------------------------------
# Clean / deps
# ---------------------------------------------------------------------------

[windows]
clean:
    if (Test-Path build) { Remove-Item -Recurse -Force build }
    New-Item -ItemType Directory -Force build | Out-Null

[unix]
clean:
    rm -rf build
    mkdir -p build

rebuild: clean build

deps:
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

[windows]
deps-rebuild:
    if (Test-Path vendor/build) { Remove-Item -Recurse -Force vendor/build }
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

[unix]
deps-rebuild:
    rm -rf vendor/build
    cmake -S . -B vendor/build -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build vendor/build

all: deps build

[windows]
kne-example:
    New-Item -ItemType Directory -Force build/kne-extensions/hello_kne | Out-Null
    odin build include/sdk/examples/odin -build-mode:dll -out:build/kne-extensions/hello_kne/hello_kne.{{dll_ext}}
    Copy-Item include/sdk/examples/odin/extension.json build/kne-extensions/hello_kne/extension.json -Force

[unix]
kne-example:
    mkdir -p build/kne-extensions/hello_kne
    odin build include/sdk/examples/odin -build-mode:dll -out:build/kne-extensions/hello_kne/hello_kne.{{dll_ext}}
    cp -f include/sdk/examples/odin/extension.json build/kne-extensions/hello_kne/extension.json

kne-test: kne-example
    odin run tests/kne_extension_smoke.odin -file

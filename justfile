# justfile (Windows + Linux)

# Windows uses PowerShell; Linux/macOS use just's default (sh).
set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]

git_commit := `git rev-parse --short HEAD`
git_branch := `git rev-parse --abbrev-ref HEAD`

version := "1.19.5-dev"

exe     := if os() == "windows" { ".exe" } else { "" }
dll_ext := if os() == "windows" { "dll" } else { "so" }
python  := if os() == "windows" { "python" } else { "python3" }
resolve := if os() == "windows" { "Resolve-Path" } else { "realpath" }

# MSVC-only linker flags; not applicable on Linux
debug_linker := if os() == "windows" { '-extra-linker-flags:"/LTCG /IGNORE:4099"' } else { "" }

gns_linker := if os() == "linux" { '-extra-linker-flags:"-L${PWD}/vendor/build/lib -Wl,-rpath,\$ORIGIN/../vendor/build/lib -Wl,-rpath,\$ORIGIN -Wl,--export-dynamic-symbol=Kinemium_*"' } else if os() == "macos" { '-extra-linker-flags:"-L${PWD}/vendor/build/lib -Wl,-rpath,@loader_path/../vendor/build/lib -Wl,-rpath,@loader_path"' } else { "" }

default:
    @just --list

build:
    odin build src -o:speed -out:build/kinemium{{exe}} {{gns_linker}}

debug:
    odin build src -debug -out:build/kinemium-debug{{exe}} {{debug_linker}} -define:TRACY_ENABLE=true {{gns_linker}}

[windows]
_kill:
    @Get-Process kinemium -ErrorAction SilentlyContinue | Stop-Process -Force

[unix]
_kill:
    @pkill -x kinemium || true

release: _kill
    odin build src -o:speed -out:build/kinemium{{exe}} -define:BUILD_TARGET=editor -define:RUNTIME_VERSION_DISPLAY={{version}} -define:RUNTIME_GIT_ENABLED=true -define:RUNTIME_GIT_COMMIT={{git_commit}} -define:RUNTIME_GIT_BRANCH={{git_branch}} {{gns_linker}}

[windows]
wasm:
    & ./tools/build_wasm.ps1

[unix]
wasm-setup:
    bash ./tools/setup_wasm.sh

[unix]
wasm:
    bash ./tools/build_wasm.sh editor

wasm-serve:
    @{{python}} -c "from pathlib import Path; assert Path('build/web/kinemium_engine.wasm').is_file(), 'Run just wasm successfully first'"
    {{python}} -m http.server 8000 --bind 127.0.0.1 --directory build/web

[windows]
wasm-client address="" port="":
    & ./tools/build_wasm_client.ps1 -Address "{{address}}" -Port "{{port}}"

[unix]
wasm-client address="" port="":
    bash ./tools/build_wasm.sh client "{{address}}" "{{port}}"

wasm-client-serve:
    @{{python}} -c "from pathlib import Path; assert Path('build/web-client/kinemium_engine.wasm').is_file(), 'Run just wasm-client successfully first'"
    {{python}} -m http.server 8001 --bind 127.0.0.1 --directory build/web-client

[windows]
android:
    & ./tools/build_android.ps1

[unix]
android:
    pwsh -NoProfile -File ./tools/build_android.ps1

run: build
    ./build/kinemium{{exe}}

# Use the sibling editor checkout directly while developing, without GitHub or the remote archive.
build-local-editor editor_dir="../kinemium-editor/internal":
    odin build src -o:speed -out:build/kinemium{{exe}} {{gns_linker}}

# Select the editor at runtime, not at engine compilation.
run-local-editor editor_dir="../kinemium-editor/internal": (build-local-editor editor_dir)
    {{python}} tools/run_local_editor.py "{{absolute_path(editor_dir)}}" "./build/kinemium{{exe}}"

# Reuse an existing engine binary when changing only Luau editor code.
run-editor-source editor_dir="../kinemium-editor/internal":
    {{python}} tools/run_local_editor.py "{{absolute_path(editor_dir)}}" "./build/kinemium{{exe}}"

run-debug: debug
    ./build/kinemium-debug{{exe}}

run-sandbox script="src/sandboxed/internals/gui/mainframe.luau": debug
    ./build/kinemium-debug{{exe}} --script "{{script}}"

tests_services := '''
    jolt_bindings_smoke
    jolt_threading_smoke
    part_teardown_smoke
    part_body_churn_smoke
    part_nil_body_smoke
    physics_sleep_tuning_smoke
    physics_collider_smoke
    capsule_part_smoke
    workspace_physics_smoke
    world2d_smoke
    world2d_editor_smoke
    instances2d_smoke
    part_gravity_smoke
    part_surface_smoke
    aerodynamics_service_smoke
    aseprite_service_smoke
    editable_sound_smoke
    icon_service_smoke
    localization_smoke
    localization_table_smoke
    playtest_tree_smoke
    editor_docking_smoke
    vr_service_smoke
    hinge_constraint_smoke
    spring_constraint_smoke
    rope_constraint_smoke
    attachment_joint_smoke
    attachment_joint_weld_smoke
    imported_constraints_smoke
    imported_constraint_assembly_smoke
    local_collision_group_smoke
    gpu_compute_smoke
    roblox_parity_smoke
    luau_typecheck_smoke
    reported_regressions
    update_version_smoke
    security_sandbox_vm
    task_scheduler_sleep_perf_smoke
    parallel_luau_smoke
    character_controller_smoke
    character_tuning_smoke
    character_cancollide_smoke
    cloth_collision_smoke
    cloth_pins_smoke
    cloth_config_smoke
    cloth_rigid_collision_smoke
    softbody_smoke
    softbody_collision_smoke
    terrain_character_ground_smoke
    terrain_surface_jump_smoke
    character_push_smoke
    mouse_smoke
    highlight_smoke
    handles_smoke
    lighting_smoke
    particle_emitter_smoke
    material_catalog_smoke
    water_buoyancy_camera_smoke
    terrain_service_smoke
    terrain_sdf_smoke
    terrain_collision_smoke
    playtest_output_smoke
    webview_service_smoke
    template_platform_smoke
    platform_export_smoke
    filesystem_copy_smoke
    datastore_smoke
    messaging_service_smoke
    memory_store_smoke
    plugin_api_smoke
    marketplace_plugin_smoke
'''

tests_gui := '''
    gif_image_smoke
    gui_component_smoke
    player_gui_smoke
    viewport_frame_smoke
    gui_hit_smoke
    gui_hit_test_smoke
    gui_rotation_smoke
    gui_layout_smoke
    screen_gui_clip_smoke
    vr_gui_smoke
    surface_gui_input_smoke
'''

tests_serializer := '''
    serializer_smoke
    serializer_depth_smoke
    kine_format_scale_smoke
    asset_portability_smoke
    part_operation_smoke
    kine_map_smoke
    kine_terrain_smoke
'''

tests_replication := '''
    replicator_loopback_smoke
    part_surface_network_smoke
    replication_constraint_smoke
    replicator_multi_peer_smoke
    replication_remote_smoke
    replication_remote_concurrent_smoke
    replication_remote_zstd_smoke
    replication_compact_codec_smoke
    replication_unreliable_remote_smoke
    replication_breadth_smoke
    cloth_replication_smoke
    character_replication_smoke
    physics_model_smoke
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
    for t in $(printf '%s' '{{tests}}'); do
        output=$(odin run "tests/$t.odin" -file {{gns_linker}} 2>&1)
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
    odin test src {{gns_linker}}
    odin test src/engine/assetstore {{gns_linker}}
    @just test-serializer
    @just test-replication
    @just test-services
    @just test-gui

test-services: (_run-tests "service" tests_services)

test-gui: (_run-tests "gui" tests_gui)

# Native visual regressions require a Vulkan-capable display/device.
test-imported-visuals: (_run-tests "imported visuals" "sky_render_smoke billboard_gui_render_smoke special_mesh_render_smoke part_surface_render_smoke cloth_render_smoke")

# Effects require a native Vulkan-capable display/device.
test-lighting-effects: (_run-tests "lighting effects" "volumetric_lighting_smoke advanced_lighting_smoke material_shader_render_smoke")

[linux]
test-postprocess-chain-headless:
    LD_LIBRARY_PATH="${PWD}/vendor/build/lib:${LD_LIBRARY_PATH:-}" odin run tests/postprocess_chain_headless_smoke.odin -file {{gns_linker}}

[linux]
test-odin-compositor:
    cmake --build vendor/build --target kine_vulkan_compositor KinemiumLibs --parallel 6
    odin check src
    odin test src/engine/renderer/compositor '-extra-linker-flags:-Lvendor/build/lib -Wl,-rpath,$ORIGIN/../vendor/build/lib -Wl,-rpath,$ORIGIN -lvulkan -lstdc++ -lc++ -lc++abi -lEGL -lGL'
    if [ "${KINE_SKIP_COMPOSITOR_GPU_TESTS:-0}" != "1" ]; then odin run tests/native_compositor_lifecycle_smoke.odin -file '-extra-linker-flags:-Lvendor/build/lib -Wl,-rpath,$ORIGIN/../vendor/build/lib -Wl,-rpath,$ORIGIN -lvulkan -lstdc++ -lc++ -lc++abi -lEGL -lGL'; fi
    if [ "${KINE_SKIP_COMPOSITOR_GPU_TESTS:-0}" != "1" ]; then odin run tests/odin_compositor_smoke.odin -file '-extra-linker-flags:-Lvendor/build/lib -Wl,-rpath,$ORIGIN/../vendor/build/lib -Wl,-rpath,$ORIGIN -lvulkan -lstdc++ -lc++ -lc++abi -lEGL -lGL'; fi
    odin build src -o:speed -out:build/kinemium-odin-release-verify -define:BUILD_TARGET=editor {{gns_linker}}

test-porter-content:
    {{python}} tests/porter_content_test.py

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
    @python ./tools/wire_engine.py --root-path .
    @odin check src

[unix]
wire:
    @python ./tools/wire_engine.py --root-path .
    @odin check src

[windows]
wire-check:
    @powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tools/wire_engine.ps1 -RootPath . -Check

[unix]
wire-check:
    @python ./tools/wire_engine.py --root-path .

fmt:
    odinfmt -w src

editor:
    odin build src -define:BUILD_TARGET=editor -out:build/kinemium-editor{{exe}} {{gns_linker}}

client:
    odin build src -define:BUILD_TARGET=client -out:build/kinemium-client{{exe}} {{gns_linker}}

player: client

server:
    odin build src -define:BUILD_TARGET=server -out:build/kinemium-server{{exe}} {{gns_linker}}

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
    odin build src -define:BUILD_TARGET=server -define:KINE_MODE=server -define:KINE_ADDRESS={{address}} -define:KINE_PORT={{port}} -define:KINE_EMBED="$({{resolve}} '{{map}}')" -out:build/kinemium-server{{exe}} {{gns_linker}}

client-bake address="" map="" port="1234":
    odin build src -define:BUILD_TARGET=client -define:KINE_MODE=client {{ if address != "" { "-define:KINE_ADDRESS=" + address + " " } else { "" } }}-define:KINE_PORT={{port}} {{ if map != "" { "-define:KINE_EMBED=\"$(" + resolve + " '" + map + "')\" " } else { "" } }}-out:build/kinemium-client{{exe}} {{gns_linker}}

custom startup target="client" noedit="false":
    odin build src -define:BUILD_TARGET={{target}} -define:LUAU_STARTUP="$({{resolve}} '{{startup}}')" -define:NOEDITOR={{noedit}} -out:build/kinemium-custom{{exe}} {{gns_linker}}

run-editor:
    odin run src -define:BUILD_TARGET=editor {{gns_linker}}

playtest map: editor
    ./build/kinemium-editor{{exe}} "{{map}}"

run-client:
    odin run src -define:BUILD_TARGET=client {{gns_linker}}

run-player: run-client

run-server:
    odin run src -define:BUILD_TARGET=server {{gns_linker}}

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
    {{if os() == "windows" { "" } else { "LD_LIBRARY_PATH=${PWD}/vendor/build/lib:${LD_LIBRARY_PATH:-}" }}} odin run tests/kne_extension_smoke.odin -file {{gns_linker}}

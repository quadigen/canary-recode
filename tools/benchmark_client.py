import argparse
import hashlib
import math
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

from kinereader import KineFile, patch_script_source


SOURCE = r"""
task.spawn(function()
    local profiler=game:GetService("ProfilerService")
    local run=game:GetService("RunService")
    task.wait(WARMUP)
    local lighting=game:GetService("Lighting")
    if ULTRA_QUALITY then
        lighting.QualityPreset=Enum.QualityPreset.Ultra
    end
    if FIXED_QUALITY then
        lighting.DynamicResolution=false
        lighting.AdaptiveShadowResolution=false
        task.wait(2)
    end
    local captureHistory=CAPTURE_HISTORY
    local measureBackend=MEASURE_BACKEND
    local measureGC=MEASURE_GC
    if measureGC then assert(profiler:SetGCProfilingEnabled(true)) end
    local function sample(name,cycle)
        print(string.format("KINE_PERF_STAGE %d %s",cycle,name))
        local times={}
        local scales={}
        local shadowSizes={}
        local queueTimes={}
        local queueSerial=0
        local passTotals,passSamples={},0
        profiler:GetFrameStats(captureHistory)
        run.Heartbeat:Wait()
        local started=os.clock()
        local previous=started
        local nextSample=started
        local missed=0
        local gpuSerial,gpuTotal,gpuCount=0,0,0
        local budget=1000/TARGET_FPS
        while os.clock()-started<DURATION do
            run.Heartbeat:Wait()
            local now=os.clock()
            local ms=(now-previous)*1000
            previous=now
            table.insert(times,ms)
            if ms>budget then missed+=1 end
            if now>=nextSample then
                local stats=profiler:GetFrameStats(false)
                table.insert(scales,stats.renderScale or 0)
                if stats.gpuFrameValid and stats.gpuFrameId~=gpuSerial then
                    gpuTotal+=stats.gpuFrameMs
                    gpuCount+=1
                    gpuSerial=stats.gpuFrameId
                end
                table.insert(shadowSizes,stats.effectiveShadowMapSize or 0)
                if stats.queueFrameValid and stats.queueFrameId~=queueSerial then
                    queueSerial=stats.queueFrameId
                    table.insert(queueTimes,stats.queueFrameMs)
                end
                if measureBackend and stats.renderPasses then
                    passSamples+=1
                    for key,count in stats.renderPasses do
                        passTotals[key]=(passTotals[key] or 0)+count
                    end
                end
                nextSample=now+(measureBackend and 0.1 or 1)
            end
        end
        if measureBackend then
            table.sort(queueTimes)
            local sum=0
            for _,ms in queueTimes do sum+=ms end
            print(string.format("KINE_PERF_QUEUE %d %s samples=%d mean=%.4f p95=%.4f",cycle,name,#queueTimes,sum/math.max(1,#queueTimes),queueTimes[math.max(1,math.ceil(#queueTimes*0.95))] or 0))
            for key,total in passTotals do
                print(string.format("KINE_PERF_PASS %d %s %s samples=%d mean=%.4f",cycle,name,key,passSamples,total/math.max(1,passSamples)))
            end
            local zones={}
            local count=math.min(profiler.FrameCount,256,#times)
            for i=1,count do
                local rec=profiler:GetFrameRecord(i)
                if rec and rec.zones then
                    for _,zone in rec.zones do zones[zone.name]=(zones[zone.name] or 0)+zone.ms end
                end
            end
            for key,value in zones do
                if value/math.max(1,count)>0.03 then
                    print(string.format("KINE_PERF_ZONE %d %s %s %.5f",cycle,name,key,value/math.max(1,count)))
                end
            end
        end
        if measureGC then
            local fast,slow={n=0,gc=0,max=0},{n=0,gc=0,max=0}
            local count=math.min(profiler.FrameCount,#times,512)
            for i=1,count do
                local record=profiler:GetFrameRecord(i)
                if record then
                    local group=record.frameMs>1000/TARGET_FPS and slow or fast
                    group.n+=1
                    group.gc+=record.gcMs or 0
                    group.max=math.max(group.max,record.gcMaxStepMs or 0)
                end
            end
            print(string.format("KINE_PERF_GC %d %s fast=%d slow=%d fast_gc=%.6f slow_gc=%.6f fast_max=%.6f slow_max=%.6f",cycle,name,fast.n,slow.n,fast.gc/math.max(fast.n,1),slow.gc/math.max(slow.n,1),fast.max,slow.max))
        end
        table.sort(times)
        local total=0
        for _,ms in times do total+=ms end
        local n=#times
        local function percentile(q)
            return times[math.max(1,math.ceil(n*q))] or 0
        end
        local sum=0
        for _,v in scales do sum+=v end
        table.sort(scales)
        table.sort(shadowSizes)
        print(string.format("KINE_PERF_DETAIL %d %s %.6f %d %d %.9g %.9g %d %.6f",cycle,name,percentile(0.999),missed,#scales,scales[1] or 0,scales[#scales] or 0,gpuCount,gpuTotal/math.max(1,gpuCount)))
        print(string.format("KINE_PERF_SHADOW %d %s %d %d",cycle,name,shadowSizes[1] or 0,shadowSizes[#shadowSizes] or 0))
        print(string.format("KINE_PERF_RESULT %d %s %d %.6f %.6f %.6f %.6f %.6f %.6f",cycle,name,n,1000*n/math.max(total,0.0001),percentile(0.5),percentile(0.95),percentile(0.99),times[n] or 0,sum/math.max(1,#scales)))
    end
    local fixedOrigin=CAMERA_ORIGIN
    for cycle=1,CYCLES do
        local camera=workspace.CurrentCamera
        local oldType=camera.CameraType
        local original=camera.CFrame
        if fixedOrigin then
            camera.CameraType=Enum.CameraType.Scriptable
            camera.CFrame=fixedOrigin
        end
        sample("stationary",cycle)
        local origin=fixedOrigin or camera.CFrame
        local movingStarted=os.clock()
        camera.CameraType=Enum.CameraType.Scriptable
        run:BindToRenderStep("KineBenchmarkCamera",10000,function()
            local elapsed=os.clock()-movingStarted
            camera.CFrame=origin+Vector3.new(math.sin(elapsed*3)*0.12,0,math.cos(elapsed*3)*0.12)
        end)
        local ok,err=pcall(function() sample("moving",cycle) end)
        run:UnbindFromRenderStep("KineBenchmarkCamera")
        camera.CFrame=origin
        if not fixedOrigin then camera.CameraType=oldType end
        if not ok then error(err) end
        sample("repeat",cycle)
        if fixedOrigin then
            camera.CFrame=original
            camera.CameraType=oldType
        end
    end
    if measureGC then profiler:SetGCProfilingEnabled(false) end
    print("KINE_PERF_DONE")
end)
"""


def stop_process(process):
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def configure_fullscreen(process, existing_ids):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Client exited before fullscreen")
        windows = json.loads(subprocess.check_output(["niri", "msg", "--json", "windows"], text=True))
        window = next((w for w in windows if w.get("pid") == process.pid and w["id"] not in existing_ids), None)
        if window is None:
            candidates = [w for w in windows if w["id"] not in existing_ids and w.get("title") == "Kinemium Client" and w.get("app_id") == "kinemium"]
            xwindows = subprocess.run(["xdotool", "search", "--pid", str(process.pid)], capture_output=True, text=True) if candidates else None
            if len(candidates) == 1 and xwindows is not None and xwindows.returncode == 0 and xwindows.stdout.strip():
                window = candidates[0]
        if window is not None:
            subprocess.run(["niri", "msg", "action", "fullscreen-window", "--id", str(window["id"])], check=True)
            return
        time.sleep(0.25)
    raise TimeoutError("Client window not found for fullscreen")


def sample_gpu_telemetry():
    fields = ("index", "temperature.gpu", "clocks.current.graphics", "utilization.gpu", "power.draw", "memory.used")
    try:
        output = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=" + ",".join(fields), "--format=csv,noheader,nounits"],
            text=True, stderr=subprocess.DEVNULL, timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    rows = []
    for line in output.splitlines():
        values = [value.strip() for value in line.split(",")]
        if len(values) != len(fields):
            continue
        row = {}
        for name, value in zip(fields, values):
            try:
                row[name] = float(value)
            except ValueError:
                row[name] = None
        rows.append(row)
    return rows


def check_gpu_temperature(rows, limit):
    if limit is None:
        return
    temperatures = [row.get("temperature.gpu") for row in rows]
    if not temperatures or any(value is None or not math.isfinite(value) for value in temperatures):
        raise RuntimeError("GPU thermal guard stopped: temperature telemetry unavailable")
    peak = max(temperatures)
    if peak >= limit:
        raise RuntimeError(f"GPU thermal guard stopped: {peak:.1f} C >= {limit:.1f} C")


def fingerprint(path):
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
        return {"path": str(path.resolve()), "sha256": digest, "bytes": os.fstat(stream.fileno()).st_size}


def authored_camera(document, path):
    if path is None:
        return None
    camera = next((item for item in document.all if item.path() == path and item.class_name == "Camera"), None)
    transform = camera.properties.get("CFrame") if camera else None
    keys = ("x", "y", "z", "r00", "r01", "r02", "r10", "r11", "r12", "r20", "r21", "r22")
    if getattr(transform, "type", None) != "CFrame" or not all(math.isfinite(transform.fields[k]) for k in keys):
        raise ValueError(f"No valid authored Camera CFrame at {path}")
    return [transform.fields[k] for k in keys]


def analyze_output(log, args, authored_shadow):
    expected = [(cycle, stage) for cycle in range(1, args.cycles + 1) for stage in ("stationary", "moving", "repeat")]
    expected_size = list(map(int, args.expect_size.split("x"))) if args.expect_size else None
    budget = 1000 / args.target
    states = []
    rows = []
    sequence = []
    active = None
    state = None
    stage_states = []
    detail = shadow = None
    format_ok = True
    connected = scene_ready = False
    for line in log.splitlines():
        if line.startswith("Network client connected as "):
            connected = True
        elif line.startswith("Network scene ready;"):
            scene_ready = True
        swapchain = re.fullmatch(r"\[Kine\] active swapchain extent=(\d+)x(\d+) present=(\w+) vendor=([\da-fA-F]+) device=([\da-fA-F]+) gpu=(.+)", line)
        if swapchain:
            w, h, mode, vendor, device, gpu = swapchain.groups()
            state = dict(size=[int(w), int(h)], present=mode, vendor=vendor.lower(), device=device, gpu=gpu)
            states.append(state)
            if active:
                stage_states.append(state)
            continue
        marker = re.search(r"\bKINE_PERF_(STAGE|DETAIL|SHADOW|RESULT) (\d+) (stationary|moving|repeat)(?: (.*))?$", line)
        if not marker:
            continue
        kind, cycle, stage, fields = marker.groups()
        key = (int(cycle), stage)
        if kind == "STAGE":
            format_ok &= active is None and connected and scene_ready
            sequence.append(key)
            active, stage_states, detail, shadow = key, [state], None, None
            continue
        if key != active:
            format_ok = False
            continue
        fields = (fields or "").split()
        try:
            if kind == "DETAIL":
                p999, missed, samples, minimum, maximum, gpu_count, gpu_mean = fields
                format_ok &= detail is None
                detail = dict(p999_ms=float(p999), budget_misses=int(missed), quality_samples=int(samples),
                              min_render_scale=float(minimum), max_render_scale=float(maximum),
                              gpu_samples=int(gpu_count), gpu_mean_ms=float(gpu_mean) if int(gpu_count) else None)
            elif kind == "SHADOW":
                low, high = map(int, fields)
                format_ok &= shadow is None
                shadow = dict(shadow_map_min=low, shadow_map_max=high)
            else:
                count, fps, median, p95, p99, maximum, scale = fields
                count = int(count)
                row = dict(cycle=key[0], stage=stage, count=count, fps=float(fps), median_ms=float(median),
                           p95_ms=float(p95), p99_ms=float(p99), maximum_ms=float(maximum), render_scale=float(scale))
                if detail:
                    row.update(detail)
                    row["over_budget_percent"] = 100 * detail["budget_misses"] / count if count else None
                if shadow:
                    row.update(shadow)
                quality_ok = bool(detail and shadow and detail["quality_samples"] > 0 and 0 <= detail["budget_misses"] <= count)
                if args.fixed_quality:
                    quality_ok = bool(quality_ok and authored_shadow is not None and
                                      shadow["shadow_map_min"] == shadow["shadow_map_max"] == authored_shadow and
                                      detail["min_render_scale"] == detail["max_render_scale"] == 1)
                resolution_ok = expected_size is None or all(s and s["size"] == expected_size for s in stage_states)
                presentation_ok = args.present == "default" or all(s and s["present"] == args.present for s in stage_states)
                gpu_ok = all(s and (not args.nvidia or s["vendor"] == "10de") and
                             (not args.expect_gpu or args.expect_gpu.casefold() in s["gpu"].casefold()) for s in stage_states)
                row.update(quality_passed=quality_ok, resolution_passed=bool(resolution_ok),
                           presentation_passed=bool(presentation_ok), gpu_passed=gpu_ok, swapchains=stage_states)
                row["passed"] = bool(count > 0 and row["fps"] >= args.target and row["p99_ms"] <= budget
                                     and quality_ok and resolution_ok and presentation_ok and gpu_ok)
                row["strict_passed"] = row["passed"] and detail["budget_misses"] == 0
                rows.append(row)
                active = None
        except (ValueError, OverflowError):
            format_ok = False
    complete = bool(format_ok and active is None and sequence == expected and len(rows) == len(expected))
    return dict(expected_size=expected_size, resolution_passed=bool(rows and all(row["resolution_passed"] for row in rows)),
                render_sizes=[s["size"] for s in states], present_modes=[s["present"] for s in states],
                expected_gpu=args.expect_gpu, authored_shadow_size=authored_shadow, target_fps=args.target, budget_ms=budget,
                strict=args.strict, fullscreen=args.fullscreen, fixed_quality=args.fixed_quality,
                full_history=not args.lightweight or args.gc_diagnostics or args.backend_diagnostics,
                backend_diagnostics=args.backend_diagnostics, gc_diagnostics=args.gc_diagnostics,
                timing_source="monotonic client Heartbeat intervals", stages_complete=complete,
                passed=complete and all(row["strict_passed" if args.strict else "passed"] for row in rows), rows=rows)


def linux_process_sample(pid):
    try:
        base = Path("/proc") / str(pid)
        fields = (base / "stat").read_text().rsplit(")", 1)[1].split()
        cpu_seconds = (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")
        rss_bytes = int(fields[21]) * os.sysconf("SC_PAGE_SIZE")
        return {"cpu_seconds": cpu_seconds, "rss_bytes": rss_bytes}
    except (OSError, IndexError, ValueError):
        return None


def run(args, output):
    output.mkdir(parents=True, exist_ok=False)
    map_dir = output / "map"
    map_dir.mkdir()
    assets = args.map.parent / "assets"
    if assets.is_dir():
        (map_dir / "assets").symlink_to(assets, target_is_directory=True)
    document = KineFile.open(str(args.map))
    node = next((item for item in document.all if item.path() == args.bootstrap), None)
    if node is None:
        raise ValueError(f"Bootstrap script not found: {args.bootstrap}")
    camera_origin = authored_camera(document, args.camera)
    camera_luau = "CFrame.new(" + ",".join(map(str, camera_origin)) + ")" if camera_origin else "nil"
    source = SOURCE.replace("CAMERA_ORIGIN", camera_luau).replace("WARMUP", str(args.warmup)).replace("DURATION", str(args.duration)).replace("CYCLES", str(args.cycles)).replace("CAPTURE_HISTORY", "true" if not args.lightweight or args.gc_diagnostics or args.backend_diagnostics else "false").replace("MEASURE_GC", "true" if args.gc_diagnostics else "false").replace("TARGET_FPS", str(args.target)).replace("FIXED_QUALITY", "true" if args.fixed_quality else "false").replace("ULTRA_QUALITY", "true" if args.ultra else "false").replace("MEASURE_BACKEND", "true" if args.backend_diagnostics else "false")
    map_file = map_dir / args.map.name
    patch_script_source(document, node, source + chr(10) + node.properties["Source"], str(map_file))
    common = ["--playtest-host", "--address", "127.0.0.1", "--port", str(args.port), "--no-update"]
    environment = os.environ.copy()
    if args.present == "default":
        environment.pop("KINE_VULKAN_PRESENT", None)
    else:
        environment["KINE_VULKAN_PRESENT"] = args.present
    environment["MANGOHUD"] = "0"
    if args.backend_diagnostics:
        environment["KINE_VULKAN_GPU_TIMING"] = "1"
    if args.nvidia:
        environment["__NV_PRIME_RENDER_OFFLOAD"] = "1"
        environment["__VK_LAYER_NV_optimus"] = "NVIDIA_only"
    server = client = None
    gpu_samples = []
    server_log = output / "server.log"
    client_log = output / "client.log"
    try:
        if args.max_gpu_temp is not None:
            check_gpu_temperature(sample_gpu_telemetry(), args.max_gpu_temp)
        artifacts = {"map": fingerprint(args.map), "engine": fingerprint(args.engine), "benchmark_script_sha256": hashlib.sha256(source.encode()).hexdigest()}
        with server_log.open("wb") as server_file, client_log.open("wb") as client_file:
            server = subprocess.Popen([str(args.engine), "--server", "--map", str(map_file), *common], stdout=server_file, stderr=subprocess.STDOUT)
            time.sleep(2)
            if server.poll() is not None:
                raise RuntimeError(f"Server failed: {server_log}")
            existing_ids = {w["id"] for w in json.loads(subprocess.check_output(["niri", "msg", "--json", "windows"], text=True))} if args.fullscreen else set()
            client = subprocess.Popen([str(args.engine), "--client", *common], stdout=client_file, stderr=subprocess.STDOUT, env=environment)
            executable = Path(f"/proc/{client.pid}/exe")
            if executable.is_file() and not executable.samefile(args.engine):
                raise RuntimeError(f"Client executable differs from requested build: {executable.resolve()}")
            if args.fullscreen:
                configure_fullscreen(client, existing_ids)
            start_time = time.monotonic()
            deadline = start_time + args.warmup + args.duration * args.cycles * 3 + 90
            while time.monotonic() < deadline:
                log = client_log.read_text(errors="replace")
                if "KINE_PERF_DONE" in log:
                    if args.max_gpu_temp is not None:
                        check_gpu_temperature(sample_gpu_telemetry(), args.max_gpu_temp)
                    break
                if client.poll() is not None:
                    raise RuntimeError(f"Client exited early: {client_log}")
                if args.gpu_telemetry:
                    stages = re.findall(r"KINE_PERF_STAGE (\d+) (stationary|moving|repeat)", log)
                    cycle, stage = stages[-1] if stages else (0, "warmup")
                    gpus = sample_gpu_telemetry()
                    gpu_samples.append(dict(elapsed_seconds=time.monotonic()-start_time, cycle=int(cycle), stage=stage,
                                            client=linux_process_sample(client.pid), server=linux_process_sample(server.pid),
                                            gpus=gpus))
                    check_gpu_temperature(gpus, args.max_gpu_temp)
                time.sleep(1)
            else:
                raise TimeoutError(f"Benchmark timed out: {client_log}")
    finally:
        stop_process(client)
        stop_process(server)
        if args.gpu_telemetry:
            (output / "gpu_telemetry.json").write_text(json.dumps(gpu_samples, indent=2))
    lighting = next((item for item in document.all if item.class_name == "Lighting"), None)
    shadow_size = 4096 if args.ultra else lighting.properties.get("ShadowMapSize") if lighting else None
    result = analyze_output(log, args, shadow_size)
    result.update(artifacts=artifacts, camera=args.camera, camera_origin=camera_origin,
                  duration_seconds=args.duration, warmup_seconds=args.warmup, ultra=args.ultra, max_gpu_temp=args.max_gpu_temp)
    (output / "result.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2), flush=True)
    return result["passed"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", type=Path, default=Path("build/kinemium"))
    parser.add_argument("--map", type=Path, required=True)
    parser.add_argument("--bootstrap", required=True)
    parser.add_argument("--camera", help="Use this map Camera's authored CFrame for every stage")
    parser.add_argument("--expect-gpu", help="Require a case-insensitive substring of the active Vulkan GPU name")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--target", type=float, default=145)
    parser.add_argument("--duration", type=int, default=30)
    parser.add_argument("--warmup", type=int, default=20)
    parser.add_argument("--cycles", type=int, default=3)
    parser.add_argument("--port", type=int, default=19386)
    parser.add_argument("--nvidia", action="store_true")
    parser.add_argument("--gpu-telemetry", action=argparse.BooleanOptionalAction, default=None)
    parser.add_argument("--fullscreen", action="store_true")
    parser.add_argument("--expect-size", help="Require measured-stage native swapchain dimensions, e.g. 1920x1080")
    parser.add_argument("--present", choices=["default","immediate","mailbox","fifo"], default="immediate")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--lightweight", action="store_true")
    parser.add_argument("--gc-diagnostics", action="store_true")
    parser.add_argument("--backend-diagnostics", action="store_true")
    parser.add_argument("--fixed-quality", action="store_true")
    parser.add_argument("--ultra", action="store_true", help="Apply Ultra preset and require 100% scene resolution and 4096px shadows")
    parser.add_argument("--max-gpu-temp", type=float, help="Stop the benchmark at this NVIDIA GPU temperature in Celsius")
    parser.add_argument("--until-pass", action="store_true")
    args = parser.parse_args()
    if args.target <= 0 or args.duration < 1 or args.warmup < 0 or args.cycles < 1:
        parser.error("Invalid benchmark parameters")
    if args.expect_size and not re.fullmatch(r"[1-9][0-9]*x[1-9][0-9]*", args.expect_size):
        parser.error("--expect-size must be WIDTHxHEIGHT")
    if args.ultra:
        args.fixed_quality = True
    if args.max_gpu_temp is not None and (not math.isfinite(args.max_gpu_temp) or not 30 <= args.max_gpu_temp <= 95):
        parser.error("--max-gpu-temp must be between 30 and 95 Celsius")
    if args.gpu_telemetry is None:
        args.gpu_telemetry = args.nvidia
    if args.max_gpu_temp is not None:
        args.gpu_telemetry = True
    args.engine = args.engine.resolve(strict=True)
    args.map = args.map.resolve(strict=True)
    root = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="kine-client-benchmark-"))
    root.mkdir(parents=True, exist_ok=True)
    attempt = 1
    while True:
        output = root / f"attempt-{attempt:04d}"
        while output.exists():
            attempt += 1
            output = root / f"attempt-{attempt:04d}"
        print(f"Benchmark output: {output}", flush=True)
        if run(args, output):
            return 0
        if not args.until_pass:
            return 1
        attempt += 1


if __name__ == "__main__":
    raise SystemExit(main())

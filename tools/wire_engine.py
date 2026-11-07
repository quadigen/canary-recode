#!/usr/bin/env python3
"""Engine wiring generator (Python port of tools/wire_engine.ps1).

Usage:
    python3 tools/wire_engine.py [--root-path PATH] [--check]
"""
import argparse
import os
import re
import sys

NL = "\n"


class WireError(Exception):
    pass


ROOT = ""
CHECK = False
CHANGED = []
OUTDATED = []


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def rel(path):
    full = os.path.abspath(path)
    prefix = ROOT.rstrip("\\/") + os.sep
    if full.startswith(prefix):
        return full[len(prefix):].replace("\\", "/")
    return full.replace("\\", "/")


def sort_key(s):
    # Approximates PowerShell's culture-aware Sort-Object (ICU): case-insensitive,
    # with '_' sorting before digits and letters.
    return (s.lower().replace("_", "\x01"), s)


def read_text(path):
    with open(path, "r", encoding="utf-8-sig", newline="") as f:
        return f.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def read_lines(path):
    text = read_text(path)
    lines = re.split(r"\r\n|\n|\r", text)
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def get_odin_files(directory, exclude=()):
    names = [
        n for n in os.listdir(directory)
        if os.path.isfile(os.path.join(directory, n))
        and n.endswith(".odin")
        and n not in exclude
        and not n.endswith(".generated.odin")
    ]
    names.sort(key=sort_key)
    return [os.path.join(directory, n) for n in names]


def get_unique_matches(files, pattern):
    names = set()
    rx = re.compile(pattern)
    for f in files:
        source = read_text(f)
        for m in rx.finditer(source):
            names.add(m.group("name"))
    return sorted(names, key=sort_key)


def to_snake_case(name):
    a = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", name)
    b = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", a)
    return b.lower()


def set_generated_region(path, region, generated_lines):
    lines = read_lines(path)
    begin_marker = f"// wire:begin {region}"
    end_marker = f"// wire:end {region}"
    begin = end = -1
    for i, line in enumerate(lines):
        if line.strip() == begin_marker:
            if begin != -1:
                raise WireError(f"Duplicate '{begin_marker}' in {rel(path)}")
            begin = i
        if line.strip() == end_marker:
            if end != -1:
                raise WireError(f"Duplicate '{end_marker}' in {rel(path)}")
            end = i
    if begin < 0 or end < 0 or end <= begin:
        raise WireError(f"Missing or invalid wire region '{region}' in {rel(path)}")

    result = lines[: begin + 1] + list(generated_lines) + lines[end:]
    new_text = NL.join(result) + NL
    old_text = read_text(path)
    if old_text == new_text:
        return
    if CHECK:
        OUTDATED.append(rel(path))
        return
    write_text(path, new_text)
    CHANGED.append(rel(path))


def set_generated_file(path, lines):
    new_text = NL.join(lines) + NL
    old_text = read_text(path) if os.path.exists(path) else ""
    if old_text == new_text:
        return
    if CHECK:
        OUTDATED.append(rel(path))
        return
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    write_text(path, new_text)
    CHANGED.append(rel(path))


def add_wire_service_tag(path):
    lines = read_lines(path)
    insert_after = -1
    for i, line in enumerate(lines):
        if re.match(r"^#\+build[ \t]+!js[ \t]*$", line, re.I):
            insert_after = i
            break
    if insert_after < 0:
        for i, line in enumerate(lines):
            if re.match(r"^package[ \t]+", line, re.I):
                insert_after = i
                break
    if insert_after < 0:
        raise WireError(f"Cannot find a place to add wire:service in {rel(path)}")

    if CHECK:
        OUTDATED.append(rel(path))
        return

    lines.insert(insert_after + 1, "// wire:service")
    write_text(path, NL.join(lines) + NL)
    CHANGED.append(rel(path))


def find_duplicates(items):
    seen, dups = set(), []
    for i in items:
        if i in seen and i not in dups:
            dups.append(i)
        seen.add(i)
    return dups


# ---------------------------------------------------------------------------
# Main generation
# ---------------------------------------------------------------------------

def run():
    # ---- classes -------------------------------------------------------
    classes_path = os.path.join(ROOT, "src/engine/classes")
    class_files = get_odin_files(classes_path, ["Registry.odin"])
    class_procedures = get_unique_matches(
        class_files,
        r"(?m)^[ \t]*(?P<name>Register_[A-Za-z][A-Za-z0-9_]*)[ \t]*::[ \t]*proc[ \t]*\([ \t\r\n]*registry[ \t]*:[ \t]*\^Registry\b",
    )
    class_procedures.sort(key=lambda n: (0 if n == "Register_Instance" else 1, sort_key(n)))
    set_generated_region(
        os.path.join(classes_path, "Registry.odin"),
        "classes",
        [f"\t{p}(registry)" for p in class_procedures],
    )

    # ---- constraints ---------------------------------------------------
    constraint_entries = []
    constraint_class_rx = re.compile(
        r"(?s)\b(?P<symbol>[A-Za-z][A-Za-z0-9_]*)_Class[ \t]*:=[ \t]*Class_Info[ \t]*\{(?P<body>.*?)\}"
    )
    constraint_step_rx = re.compile(
        r"(?m)^[ \t]*(?P<name>[A-Za-z][A-Za-z0-9_]*_step)[ \t]*::[ \t]*proc[ \t]*\("
    )
    for f in class_files:
        source = read_text(f)
        for cm in constraint_class_rx.finditer(source):
            body = cm.group("body")
            if not re.search(r"\bparent[ \t]*=[ \t]*&Constraint_Class\b", body, re.I):
                continue
            symbol = cm.group("symbol")
            step_name = f"{symbol}_step"
            has_step = any(s.group("name") == step_name for s in constraint_step_rx.finditer(source))
            if not has_step:
                raise WireError(f"{symbol}_Class is a constraint but {rel(f)} has no {step_name} proc")
            constraint_entries.append((symbol, step_name))
    constraint_entries.sort(key=lambda e: sort_key(e[0]))
    dups = find_duplicates([e[0] for e in constraint_entries])
    if dups:
        raise WireError(f"Duplicate constraint class '{dups[0]}'")
    lines = [
        "package classes",
        "",
        "// Generated by just wire. Do not edit by hand.",
        "",
        "Constraint_Steps := [?]Constraint_Step_Entry{",
    ]
    for symbol, step in constraint_entries:
        lines.append(f"\t{{&{symbol}_Class, {step}}},")
    lines.append("}")
    set_generated_file(os.path.join(classes_path, "ConstraintRegistry.generated.odin"), lines)

    # ---- services ------------------------------------------------------
    services_path = os.path.join(ROOT, "src/engine/services")
    service_files = get_odin_files(services_path, ["Registry.odin"])
    service_class_rx = re.compile(
        r"(?m)^[ \t]*(?P<name>Register_[A-Za-z][A-Za-z0-9_]*_Class)[ \t]*::[ \t]*proc[ \t]*\([ \t\r\n]*registry[ \t]*:[ \t]*\^classes\.Registry\b"
    )
    native_only_rx = re.compile(r"(?m)^#\+build[ \t]+!js[ \t\r]*$", re.I)

    service_class_procs = []
    for f in service_files:
        source = read_text(f)
        native_only = bool(native_only_rx.search(source))
        for m in service_class_rx.finditer(source):
            service_class_procs.append((m.group("name"), native_only))

    def svc_rank(name):
        if name == "Register_DataModel_Class":
            return 0
        if name == "Register_Service_Class":
            return 1
        return 2

    service_class_procs.sort(key=lambda p: (svc_rank(p[0]), sort_key(p[0])))
    seen = set()
    service_class_lines = []
    for name, native_only in service_class_procs:
        if name in seen:
            raise WireError(f"Duplicate service class registration procedure '{name}'")
        seen.add(name)
        if native_only:
            service_class_lines.append(f"\twhen ODIN_OS != .JS {{ {name}(registry.classes) }}")
        else:
            service_class_lines.append(f"\t{name}(registry.classes)")
    set_generated_region(os.path.join(services_path, "Registry.odin"), "service-classes", service_class_lines)

    global_tag_rx = re.compile(
        r'(?m)^[ \t]*//[ \t]*wire:service(?:[ \t]+global="(?P<global>[A-Za-z_][A-Za-z0-9_]*)")?[ \t\r]*$'
    )
    service_entries = []
    for f in service_files:
        source = read_text(f)
        gm = global_tag_rx.search(source)
        global_name = (gm.group("global") or "") if gm else ""
        is_service = False

        for reg in service_class_rx.finditer(source):
            procedure = reg.group("name")
            symbol = procedure[len("Register_"): len(procedure) - len("_Class")]
            class_rx = re.compile(
                r"(?s)\b" + re.escape(symbol) + r"_Class[ \t]*:=[ \t]*classes\.Class_Info[ \t]*\{(?P<body>.*?)\}"
            )
            cm = class_rx.search(source)
            if not cm:
                raise WireError(f"Cannot find {symbol}_Class metadata in {rel(f)}")
            body = cm.group("body")
            if not re.search(r"\bparent[ \t]*=[ \t]*&Service_Class\b", body, re.I):
                continue
            is_service = True
            nm = re.search(r'\bname[ \t]*=[ \t]*"(?P<name>[^"]+)"', body)
            if not nm:
                raise WireError(f"{symbol}_Class has no string name in {rel(f)}")
            service_entries.append({
                "Name": nm.group("name"),
                "ClassName": nm.group("name"),
                "GlobalName": global_name,
                "NativeOnly": bool(native_only_rx.search(source)),
            })

        if is_service and not gm:
            add_wire_service_tag(f)

    def service_registration(s):
        if s["GlobalName"]:
            return f'Register_Service(registry, "{s["Name"]}", "{s["ClassName"]}", "{s["GlobalName"]}")'
        return f'Register_Service(registry, "{s["Name"]}", "{s["ClassName"]}")'

    seen = set()
    service_lines = []
    for s in sorted(service_entries, key=lambda e: sort_key(e["Name"])):
        if s["Name"] in seen:
            raise WireError(f"Duplicate wired service '{s['Name']}'")
        seen.add(s["Name"])
        reg = service_registration(s)
        if s["NativeOnly"]:
            service_lines.append(f"\twhen ODIN_OS != .JS {{ {reg} }}")
        else:
            service_lines.append(f"\t{reg}")
    set_generated_region(os.path.join(services_path, "Registry.odin"), "services", service_lines)

    # ---- datatypes -----------------------------------------------------
    datatypes_path = os.path.join(ROOT, "src/engine/datatypes")
    datatype_files = get_odin_files(datatypes_path, ["LuaRegistry.odin"])
    bindings = get_unique_matches(
        datatype_files, r"(?m)^[ \t]*(?P<name>[A-Za-z][A-Za-z0-9_]*)_Luau_Binding[ \t]*::[ \t]*proc\b"
    )
    installers = get_unique_matches(
        datatype_files, r"(?m)^[ \t]*(?P<name>[A-Za-z][A-Za-z0-9_]*)_Install_Fields[ \t]*::[ \t]*proc\b"
    )
    missing_installers = [b for b in bindings if b not in installers]
    missing_bindings = [i for i in installers if i not in bindings]
    if missing_installers:
        raise WireError(f"Datatype bindings missing *_Install_Fields: {', '.join(missing_installers)}")
    if missing_bindings:
        raise WireError(f"Datatype installers missing *_Luau_Binding: {', '.join(missing_bindings)}")

    datatype_entries = sorted(
        ({"Name": b, "Field": to_snake_case(b)} for b in bindings),
        key=lambda e: sort_key(e["Name"]),
    )
    dup_fields = find_duplicates([e["Field"] for e in datatype_entries])
    if dup_fields:
        raise WireError(f"Datatype names collide when lowercased: {', '.join(dup_fields)}")
    datatype_tag_base = 64
    native_userdata_max_tag = 127
    if len(datatype_entries) > (native_userdata_max_tag - datatype_tag_base + 1):
        raise WireError(
            f"Too many wired datatypes for Luau userdata tags {datatype_tag_base}..{native_userdata_max_tag}"
        )

    reg_path = os.path.join(datatypes_path, "LuaRegistry.odin")
    set_generated_region(reg_path, "datatype-fields",
                         [f"\t{e['Field']}: vm.Userdata_Binding," for e in datatype_entries])
    set_generated_region(reg_path, "datatype-bindings",
                         [f"\tregistry.{e['Field']} = {e['Name']}_Luau_Binding()" for e in datatype_entries])
    set_generated_region(reg_path, "datatype-tags",
                         [f"\tregistry.{e['Field']}.tag = DATATYPE_TAG_BASE + {i}"
                          for i, e in enumerate(datatype_entries)])
    ctx_lines = []
    for e in datatype_entries:
        ctx_lines.append(f"\tregistry.{e['Field']}.ctx = &registry.{e['Field']}")
        ctx_lines.append(f"\tregistry.{e['Field']}.owner = registry")
    set_generated_region(reg_path, "datatype-contexts", ctx_lines)
    set_generated_region(
        reg_path, "datatype-libraries",
        [f'\tinstall_library(vm_state, "{e["Name"]}", &registry.{e["Field"]}, {e["Name"]}_Install_Fields)'
         for e in datatype_entries],
    )

    # KNE datatype dispatch
    datatype_type_by_name = {}
    datatype_has_registry = {}
    for f in datatype_files:
        source = read_text(f)
        for name in bindings:
            m = re.search(r"(?s)Push_" + re.escape(name) + r"[ \t]*::[ \t]*proc[ \t]*\((?P<params>[^)]*)\)", source)
            if not m:
                continue
            params = m.group("params")
            type_matches = list(re.finditer(r":[ \t]*(?P<type>[A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:,|$)", params))
            if not type_matches:
                continue
            datatype_type_by_name[name] = type_matches[-1].group("type")
            datatype_has_registry[name] = bool(
                re.search(r"(?<![A-Za-z0-9_])registry(?![A-Za-z0-9_])", params, re.I)
            )
    missing_types = [e["Name"] for e in datatype_entries if e["Name"] not in datatype_type_by_name]
    if missing_types:
        raise WireError(
            f"Datatype Push_<Name> procs missing or have an unexpected signature: {', '.join(missing_types)}"
        )

    kne_kind_by_name = {
        "Vector2": 20, "Vector3": 21, "Vector2int16": 22, "Vector3int16": 23,
        "CFrame": 24, "Color3": 25, "UDim": 26, "UDim2": 27, "Ray": 28, "Rect": 29,
        "Region3": 30, "Region3int16": 31, "NumberRange": 32,
        "NumberSequenceKeypoint": 33, "ColorSequenceKeypoint": 34,
        "Axes": 35, "Faces": 36, "PhysicalProperties": 37, "Quaternion": 38,
        "TweenInfo": 39, "DateTime": 40, "UniqueId": 41, "PathWaypoint": 42,
        "SecurityCapabilities": 43, "DockWidgetPluginGuiInfo": 44,
    }

    if len(datatype_entries) > 36:
        raise WireError("Engine datatype tags overlap the extension tag range")

    k = [
        "package extensions",
        "",
        "// Generated by just wire. Do not edit by hand.",
        "",
        'import datatypes "../datatypes"',
        'import vm "../vm"',
        "",
        "KNE_Engine_Datatype :: struct {",
        "\tname:  string,",
        "\tfield: string,",
        "\ttag:   u32,",
        "\tkind:  KNE_Value_Kind,",
        "\tsize:  int,",
        "\tpush:  proc(L: ^vm.State, registry: ^datatypes.Registry, handle: rawptr),",
        "\tget:   proc(L: ^vm.State, index: int, registry: ^datatypes.Registry) -> rawptr,",
        "}",
        "",
    ]
    for e in datatype_entries:
        t = datatype_type_by_name[e["Name"]]
        k.append(f"kne_push_{e['Field']} :: proc(L: ^vm.State, registry: ^datatypes.Registry, handle: rawptr) {{")
        if datatype_has_registry[e["Name"]]:
            k.append(f"\tdatatypes.Push_{e['Name']}(L, registry, (cast(^datatypes.{t})handle)^)")
        else:
            k.append(f"\tdatatypes.Push_{e['Name']}(L, (cast(^datatypes.{t})handle)^)")
        k.append("}")
        k.append("")
        k.append(
            f"kne_get_{e['Field']} :: proc(L: ^vm.State, index: int, registry: ^datatypes.Registry) -> rawptr {{"
        )
        k.append(f"\treturn datatypes.KNE_Require_Value(L, index, &registry.{e['Field']})")
        k.append("}")
        k.append("")
    k.append("KNE_Engine_Datatypes := [?]KNE_Engine_Datatype{")
    for i, e in enumerate(datatype_entries):
        t = datatype_type_by_name[e["Name"]]
        kind = kne_kind_by_name.get(e["Name"], 60)
        k.append("\t{")
        k.append(f'\t\tname = "{e["Name"]}",')
        k.append(f'\t\tfield = "{e["Field"]}",')
        k.append(f"\t\ttag = datatypes.DATATYPE_TAG_BASE + {i},")
        k.append(f"\t\tkind = KNE_Value_Kind({kind}),")
        k.append(f"\t\tsize = size_of(datatypes.{t}),")
        k.append(f"\t\tpush = kne_push_{e['Field']},")
        k.append(f"\t\tget = kne_get_{e['Field']},")
        k.append("\t},")
    k.append("}")
    set_generated_file(os.path.join(ROOT, "src/engine/extensions/KneDatatypes.generated.odin"), k)

    # ---- globals -------------------------------------------------------
    globals_path = os.path.join(ROOT, "src/engine/global")
    global_files = get_odin_files(globals_path, ["Registry.odin"])
    global_procedures = get_unique_matches(
        global_files,
        r"(?m)^[ \t]*(?P<name>Register_[A-Za-z][A-Za-z0-9_]*_Globals?)[ \t]*::[ \t]*proc[ \t]*\([ \t\r\n]*registry[ \t]*:[ \t]*\^Registry\b",
    )
    set_generated_region(os.path.join(globals_path, "Registry.odin"), "globals",
                         [f"\t{p}(registry)" for p in global_procedures])

    # ---- packages ------------------------------------------------------
    packages_path = os.path.join(ROOT, "src/engine/packages")
    package_entries = []
    package_marker_rx = re.compile(
        r'(?m)^[ \t]*//[ \t]*wire:package[ \t]+name="(?P<name>[A-Za-z_][A-Za-z0-9_]*)"[ \t\r]*$'
    )
    for dname in sorted(
        (d for d in os.listdir(packages_path) if os.path.isdir(os.path.join(packages_path, d))),
        key=sort_key,
    ):
        dpath = os.path.join(packages_path, dname)
        markers = []
        for f in get_odin_files(dpath):
            source = read_text(f)
            for m in package_marker_rx.finditer(source):
                markers.append((m.group("name"), f))
        if not markers:
            continue
        if len(markers) != 1:
            raise WireError(f"Package directory '{dname}' must contain exactly one wire:package marker")
        if markers[0][0] != dname:
            raise WireError(
                f"Package marker '{markers[0][0]}' must match directory '{dname}' in {rel(markers[0][1])}"
            )
        snake = to_snake_case(markers[0][0])
        package_entries.append({"Name": markers[0][0], "Alias": snake, "Field": snake})

    dup_pkg = find_duplicates([e["Field"] for e in package_entries])
    if dup_pkg:
        raise WireError(f"Package names collide when lowercased: {', '.join(dup_pkg)}")

    p = ["package packages", "", "// Generated by just wire. Do not edit by hand."]
    for e in package_entries:
        p.append(f'import {e["Alias"]} "{e["Name"]}"')
    p.append("")
    p.append("Package_Contexts :: struct {")
    for e in package_entries:
        p.append(f"\t{e['Field']}: {e['Alias']}.Context,")
    p.append("}")
    p.append("")
    p.append("Register_Default_Packages :: proc(registry: ^Registry) {")
    for e in package_entries:
        p.append(
            f'\tRegister_Package(registry, "{e["Name"]}", {e["Alias"]}.Install, '
            f'{e["Alias"]}.Begin_Frame, &registry.contexts.{e["Field"]})'
        )
    p.append("}")
    set_generated_file(os.path.join(packages_path, "PackageRegistry.generated.odin"), p)

    # ---- enums ---------------------------------------------------------
    enum_input = os.path.join(ROOT, "src/engine/enum/enum.odin")
    enum_output = os.path.join(ROOT, "src/engine/enum/LuaEnumGenerated.odin")
    enum_source = read_text(enum_input)
    enum_names = [
        m.group("name")
        for m in re.finditer(
            r"(?m)^(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*::\s*enum(?:\s+[^\s{]+)?\s*\{", enum_source
        )
    ]
    if not enum_names:
        raise WireError(f"No enum declarations found in {rel(enum_input)}")
    el = [
        "package engine_enums",
        "",
        "// Generated by just wire. Do not edit by hand.",
        "Register_Default_Enums :: proc(registry: ^Registry) {",
    ]
    for name in enum_names:
        el.append(f'\tRegister_Reflected_Enum(registry, "{name}", {name})')
    el.append("}")
    set_generated_file(enum_output, el)

    return {
        "classes": len(class_procedures),
        "constraints": len(constraint_entries),
        "services": len(service_entries),
        "datatypes": len(datatype_entries),
        "globals": len(global_procedures),
        "packages": len(package_entries),
        "enums": len(enum_names),
    }


def main():
    global ROOT, CHECK
    default_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description="Regenerate engine wiring.")
    ap.add_argument("--root-path", default=default_root)
    ap.add_argument("--check", action="store_true", help="Fail if generated files are out of date.")
    args = ap.parse_args()

    ROOT = os.path.abspath(args.root_path)
    CHECK = args.check

    try:
        counts = run()
    except WireError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    outdated = sorted(set(OUTDATED))
    changed = sorted(set(CHANGED))

    if CHECK and outdated:
        print(f"error: Engine wiring is out of date: {', '.join(outdated)}. Run 'just wire'.", file=sys.stderr)
        return 1

    if not changed:
        print("Engine wiring is up to date.")
    else:
        print(f"Updated engine wiring: {', '.join(changed)}")
    print(
        f"Discovered {counts['classes']} classes, {counts['constraints']} constraints, "
        f"{counts['services']} services, {counts['datatypes']} datatypes, "
        f"{counts['globals']} global hooks, {counts['packages']} packages, and {counts['enums']} enums."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
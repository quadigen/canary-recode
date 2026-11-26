#!/usr/bin/env python3
"""Generate Luau LSP definitions from registered Kinemium Odin scripting APIs.

Only exported/registered classes, enums and userdata types are emitted. Member types
are inferred conservatively; unknown native return types become `any`, rather than
claiming the engine implements an arbitrary upstream Roblox API.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from native_signatures import (CLASS_METHOD_OVERRIDES, DATATYPE_METHOD_OVERRIDES,
                               STATIC_DATATYPE_OVERRIDES, GPU_TYPES, Signature, infer_method_signature)
from expanded_api import CLASS_METHODS as MORE_CLASS_METHODS, PROPERTY_OVERRIDES, EXTRA_TYPES

IDENT = re.compile(r"^[A-Za-z_][A-Za-z_0-9]*$")
QUOTED = re.compile(r'"([A-Za-z_][A-Za-z_0-9]*)"')
ROOT = Path(__file__).resolve().parents[2]


def balanced(source: str, opening: int) -> str:
    """Return text between a balanced pair, ignoring quoted strings/comments."""
    pair = {'(': ')', '{': '}', '[': ']'}
    first = source[opening]
    assert first in pair
    stack = [pair[first]]
    pos = opening + 1
    while pos < len(source):
        char = source[pos]
        if char == '"' or char == "'":
            delim = char
            pos += 1
            while pos < len(source) and source[pos] != delim:
                if source[pos] == '\\':
                    pos += 1
                pos += 1
        elif source.startswith('//', pos):
            end = source.find('\n', pos)
            pos = len(source) if end == -1 else end
            continue
        elif source.startswith('/*', pos):
            end = source.find('*/', pos + 2)
            pos = len(source) if end == -1 else end + 2
            continue
        elif char in pair:
            stack.append(pair[char])
        elif char == stack[-1]:
            stack.pop()
            if not stack:
                return source[opening + 1:pos]
        pos += 1
    raise ValueError(f'unbalanced {first} at {opening}')


def read_files(path: Path) -> dict[Path, str]:
    return {p: p.read_text(encoding='utf-8') for p in sorted(path.glob('*.odin'))}


def get_constant_list(text: str, ident: str) -> list[str]:
    match = re.search(r'(?m)^\s*' + re.escape(ident) + r'\s*:?=\s*\[\]\s*string\s*\{', text)
    return QUOTED.findall(balanced(text, text.index('{', match.start()))) if match else []


def get_registered_list(call: str, key: str, text: str) -> list[str]:
    match = re.search(r'\b' + key + r'\s*=\s*(?:\[\]\s*string\s*\{|([A-Za-z_]\w*))', call)
    if not match:
        return []
    if match.group(1):
        return get_constant_list(text, match.group(1))
    return QUOTED.findall(balanced(call, call.index('{', match.start())))


def get_proc(text: str, name: str) -> str:
    match = re.search(r'(?m)^\s*' + re.escape(name) + r'\s*::\s*proc\b', text)
    if not match:
        return ''
    params = text.find('(', match.end())
    if params == -1:
        return ''
    # Body is the first brace after the signature; procedure bodies in these bindings
    # don't have literal braces in their signature.
    closing = params + 1 + len(balanced(text, params))
    body = text.find('{', closing)
    return balanced(text, body) if body != -1 else ''


def cases(proc: str) -> dict[str, str]:
    matches = list(re.finditer(r'(?m)^\s*case\s+((?:"[A-Za-z_]\w*"\s*,?\s*)+)\s*:', proc))
    return {name: proc[m.end():matches[i + 1].start() if i + 1 < len(matches) else len(proc)]
            for i, m in enumerate(matches) for name in QUOTED.findall(m.group(1))}


def native_type(snippet: str, name: str) -> str:
    # Prefer concrete VM push operations. No attempt is made to guess arbitrary
    # values or return types from opaque helper calls.
    if re.search(r'PushUserdataMethod', snippet):
        return 'method'
    if re.search(r'(?i)signal|event_ref|fire_event', snippet):
        return 'signal'
    specific = re.search(r'(?:datatypes\.)?Push_(Vector3|Vector2|Vector3int16|Vector2int16|UDim2|UDim|Color3|CFrame|Ray|Rect|DateTime|BrickColor|NumberRange|NumberSequence|ColorSequence|TweenInfo)\s*\(', snippet)
    if specific:
        return specific.group(1)
    for push, typ in [('PushBoolean', 'boolean'), ('PushString', 'string'), ('PushInteger', 'number'), ('PushNumber', 'number')]:
        if push in snippet:
            return typ
    return {'Name': 'string', 'ClassName': 'string', 'Parent': 'Instance?',
            'Health': 'number', 'MaxHealth': 'number', 'Anchored': 'boolean',
            'CanCollide': 'boolean', 'IsBall': 'boolean',
            'Position': 'Vector3', 'Size': 'Vector3', 'CFrame': 'CFrame',
            'Source': 'string', 'Text': 'string', 'Value': 'any',
            'Archivable': 'boolean', 'CanReplicate': 'boolean', 'IsInSandbox': 'boolean',
            'Sandboxed': 'boolean', 'NetworkId': 'number', 'UniqueId': 'UniqueId'}.get(name, 'any')


def collect_classes(engine: Path) -> dict[str, dict]:
    src = {**read_files(engine / 'classes'), **read_files(engine / 'services')}
    infos: dict[str, dict] = {}
    for path, text in src.items():
        for match in re.finditer(r'(?m)^\s*(\w+_Class)\s*:?=\s*(?:classes\.)?Class_Info\s*\{', text):
            body = balanced(text, text.index('{', match.start()))
            name = re.search(r'\bname\s*=\s*"([A-Za-z_]\w*)"', body)
            parent = re.search(r'\bparent\s*=\s*&(?:classes\.)?(\w+_Class)', body)
            if name:
                infos[match.group(1)] = dict(name=name.group(1), parent=parent.group(1) if parent else None,
                                                  props={}, methods=set(), events=set(), creatable=True, registered=False, method_bodies={})
    for path, text in src.items():
        for match in re.finditer(r'\b(?:classes\.)?Register_Class\s*\(', text):
            call = balanced(text, text.index('(', match.start()))
            symbol = re.search(r'&(\w+_Class)\b', call)
            if not symbol or symbol.group(1) not in infos:
                continue
            record = infos[symbol.group(1)]
            record['registered'] = True
            if re.search(r'\bcreatable\s*=\s*false', call):
                record['creatable'] = False
            record['props'].update({p: 'any' for p in get_registered_list(call, 'properties', text)})
            record['methods'].update(get_registered_list(call, 'methods', text))
            record['events'].update(get_registered_list(call, 'events', text))
            for key in ('get', 'set', 'namecall'):
                fn = re.search(r'\b' + key + r'\s*=\s*(\w+)', call)
                if not fn:
                    continue
                proc = get_proc(text, fn.group(1))
                if not proc:
                    continue
                for member, code in cases(proc).items():
                    kind = native_type(code, member)
                    if key == 'namecall' or kind == 'method':
                        record['methods'].add(member)
                        if key == 'namecall':
                            record['method_bodies'][member] = code
                    elif key == 'get':
                        if kind == 'signal':
                            record['events'].add(member)
                        else:
                            record['props'][member] = kind
                    elif key == 'set' and member not in record['props']:
                        record['props'][member] = 'any'
    # Most registrations are direct Register_Class(&..._Class, ...), but several
    # concrete classes are registered by iterating a Class_Info array in
    # Register_EditableImage; they were previously lost completely.
    for symbol in ('EditableImage_Instance_Class', 'Animated_Image_Class'):
        if symbol in infos:
            infos[symbol]['registered'] = True
    # Other Class_Info records still form reflected base types (GuiBase2d,
    # LayerCollector, UIComponent, Adorn, Object, ...). Preserve their actual
    # inheritance instead of flattening all descendants to Instance. These
    # type-only definitions must NOT be marked constructible.
    for obj in infos.values():
        if not obj['registered']:
            obj['creatable'] = False
    return infos


def collect_enums(engine: Path) -> dict[str, list[str]]:
    registry = (engine / 'enum' / 'LuaEnumGenerated.odin').read_text(encoding='utf-8')
    source = (engine / 'enum' / 'enum.odin').read_text(encoding='utf-8')
    registered = sorted(set(re.findall(r'Register_Reflected_Enum\s*\(\s*registry\s*,\s*"(\w+)"', registry)))
    result: dict[str, list[str]] = {}
    for enum in registered:
        match = re.search(r'(?m)^\s*' + re.escape(enum) + r'\s*::\s*enum(?:\s*:\s*\w+)?\s*\{', source)
        if not match:
            result[enum] = []
            continue
        body = balanced(source, source.index('{', match.start()))
        # Odin enum members are one per line and may carry numeric assignments.
        items = re.findall(r'(?m)^\s*([A-Za-z_]\w*)\s*(?:=\s*[^\n,]+)?\s*,?\s*(?://[^\n]*)?$', body)
        result[enum] = sorted(set(items))
    return result


def collect_datatypes(engine: Path) -> dict[str, dict]:
    reg = (engine / 'datatypes' / 'LuaRegistry.odin').read_text(encoding='utf-8')
    names = sorted(set(re.findall(r'\bregistry\.\w+\s*=\s*(\w+)_Luau_Binding\s*\(', reg)))
    files = read_files(engine / 'datatypes')
    output = {}
    for name in names:
        src = next((text for path, text in files.items() if re.search(r'(?m)^\s*' + re.escape(name) + r'_Luau_Binding\s*::', text)), '')
        lib = get_proc(src, name + '_Install_Fields') if src else ''
        if not lib:
            # Some bindings install library methods in a differently named procedure.
            lib = src
        registered_functions = {
            m.group(1): m.group(2)
            for m in re.finditer(
                r'\badd_library_function\s*\([^,]+,[^,]+,\s*"(\w+)"\s*,\s*(\w+)\s*\)',
                lib,
            )
        }
        constructors = set(registered_functions)
        fields = set(re.findall(r'\bvm\.SetField\s*\([^,]+,[^,]+,\s*"(\w+)"', lib))
        methods: set[str] = set()
        members: dict[str, str] = {}
        # Expose native userdata instance members rather than only static constructors.
        for fn in re.findall(r'(?m)^\s*(\w+(?:_index|_get|_namecall))\s*::\s*proc\b', src):
            if not fn.lower().startswith(name.lower().replace('_', '')) and name.lower() not in fn.lower().replace('_', ''):
                continue
            for key, code in cases(get_proc(src, fn)).items():
                if re.search(r'push_\w+_method|PushUserdataMethod|\bPushFunction\s*\(', code) or fn.endswith('_namecall'):
                    methods.add(key)
                elif fn.endswith(('_get', '_index')):
                    typ = native_type(code, key)
                    if typ not in ('method', 'signal'):
                        members[key] = typ
        output[name] = {'functions': constructors, 'fields': fields, 'methods': methods,
                        'members': members,
                        'function_bodies': {key: get_proc(src, func) for key, func in registered_functions.items()}}
    return output


CONSTRUCTORS = {
    'Vector2': '(x: number?, y: number?) -> Vector2',
    'Vector3': '(x: number?, y: number?, z: number?) -> Vector3',
    'Vector2int16': '(x: number?, y: number?) -> Vector2int16',
    'Vector3int16': '(x: number?, y: number?, z: number?) -> Vector3int16',
    'UDim': '(scale: number?, offset: number?) -> UDim',
    'UDim2': '(xScale: number?, xOffset: number?, yScale: number?, yOffset: number?) -> UDim2',
    'Color3': '(r: number?, g: number?, b: number?) -> Color3',
    'CFrame': '(...number) -> CFrame',
    'BrickColor': '(value: any) -> BrickColor',
    'NumberRange': '(min: number, max: number?) -> NumberRange',
    'Ray': '(origin: Vector3, direction: Vector3) -> Ray',
    'Rect': '(min: Vector2, max: Vector2) -> Rect',
    'Random': '(seed: number?) -> Random',
    'DateTime': '(unixTimestampMillis: number) -> DateTime',
}
DATATYPE_MEMBERS = {
    'Vector3': {'X': 'number', 'Y': 'number', 'Z': 'number', 'Magnitude': 'number', 'Unit': 'Vector3'},
    'Vector2': {'X': 'number', 'Y': 'number', 'Magnitude': 'number', 'Unit': 'Vector2'},
    'UDim': {'Scale': 'number', 'Offset': 'number'},
    'UDim2': {'X': 'UDim', 'Y': 'UDim'},
    'Color3': {'R': 'number', 'G': 'number', 'B': 'number'},
    'CFrame': {'Position': 'Vector3', 'LookVector': 'Vector3', 'UpVector': 'Vector3', 'RightVector': 'Vector3'},
    'NumberRange': {'Min': 'number', 'Max': 'number'},
}
SPECIAL_METHODS = {
    'Instance': {
        'Clone': 'Instance', 'Destroy': '()', 'GetChildren': '{Instance}',
        'GetDescendants': '{Instance}', 'GetFullName': 'string',
        'IsA': 'boolean', 'FindFirstChild': 'Instance?',
        'FindFirstChildOfClass': 'Instance?', 'FindFirstChildWhichIsA': 'Instance?',
        'WaitForChild': 'Instance', 'GetAttribute': 'any', 'GetTags': '{string}',
    },
    'DataModel': {'GetService': 'Instance'},
    'Humanoid': {'GetState': 'EnumItem', 'GetStateEnabled': 'boolean'},
}


def render(classes: dict[str, dict], datatypes: dict[str, dict], enums: dict[str, list[str]], studio: bool = False) -> str:
    # Several services have two Class_Info registrations with the same runtime
    # name: the full native implementation (e.g. HttpService_Class) and a
    # restricted Web_..._Class used on the JS target. A dict comprehension
    # previously selected the *last* (Web_) entry and silently discarded the
    # richer native API on Linux. Prefer the real native class for the default
    # desktop language environment, without inventing members from either.
    by_name: dict[str, tuple[str, dict]] = {}
    for symbol, record in classes.items():
        name = record['name']
        previous = by_name.get(name)
        if previous is None or (previous[0].startswith('Web_') and not symbol.startswith('Web_')):
            by_name[name] = (symbol, record)
    symbols = {s: obj['name'] for s, obj in classes.items()}
    # Animated is both a native userdata datatype and an Image subclass in
    # Kinemium. Luau cannot declare two types with the same name, so retain the
    # exact constructor className while giving the instance side a unique type.
    luau_types = {s: ('AnimatedImageInstance' if s == 'Animated_Image_Class' else obj['name'])
                  for s, obj in classes.items()}
    def parent_of(obj: dict) -> str | None:
        return symbols.get(obj['parent'])

    def is_service(name: str) -> bool:
        visited = set()
        while name in by_name and name not in visited:
            visited.add(name)
            if name == 'Service':
                return True
            name = parent_of(by_name[name][1]) or ''
        return False

    creatable = sorted(name for name, (_, obj) in by_name.items()
                       if obj['registered'] and obj['creatable'] and not is_service(name))
    services = sorted(name for name in by_name if is_service(name) and name != 'Service')
    metadata = json.dumps({'CREATABLE_INSTANCES': creatable, 'SERVICES': services}, sort_keys=True, separators=(',', ':'))
    output = ['-- Generated from Kinemium Odin runtime registrations; do not edit manually.',
              '-- Generator: canary-recode/tools/vscode-kinemium/generate_definitions.py',
              '--#METADATA#' + metadata, '',
              'declare extern type RBXScriptConnection with',
              '    Connected: boolean', '    function Disconnect(self): ()', 'end',
              'export type RBXScriptSignal<T... = ...any> = {',
              '    Connect: (self: RBXScriptSignal<T...>, callback: (T...) -> ()) -> RBXScriptConnection,',
              '    Once: (self: RBXScriptSignal<T...>, callback: (T...) -> ()) -> RBXScriptConnection,',
              '    Wait: (self: RBXScriptSignal<T...>) -> T...,', '}', '',
              'declare extern type Enum with', '    function GetEnumItems(self): {EnumItem}', 'end',
              'declare extern type EnumItem with', '    Name: string', '    Value: number', '    EnumType: Enum',
              '    function IsA(self, name: string): boolean', 'end', '']
    for name, names in sorted(enums.items()):
        output.extend([f'declare extern type Enum{name} extends EnumItem with end',
                       f'declare extern type Enum{name}_INTERNAL extends Enum with'])
        for enum_item in names:
            if IDENT.fullmatch(enum_item):
                output.append(f'    {enum_item}: Enum{name}')
        output.extend(['end', ''])
    output.extend(['type KinemiumEnums = {'])
    for name in sorted(enums):
        output.append(f'    {name}: Enum{name}_INTERNAL,')
    output.extend(['    GetEnums: (self: KinemiumEnums) -> {Enum},', '}', 'declare Enum: KinemiumEnums', ''])
    output.extend(GPU_TYPES.strip().splitlines())
    output.append('')
    output.extend(EXTRA_TYPES.strip().splitlines())
    output.append('')

    # A class with a registered ancestor is emitted after that ancestor. If an
    # ancestor is internal and unregistered, fall back to Instance/Object.
    def inherited_signature(desc: dict, method: str) -> Signature | None:
        # A subclass may redeclare an inherited method for reflection without
        # implementing a new namecall. Avoid shadowing an accurately typed
        # parent method with generic varargs in that case.
        visited = set()
        ancestor = desc['parent']
        while ancestor in classes and ancestor not in visited:
            visited.add(ancestor)
            parent = classes[ancestor]
            typed = CLASS_METHOD_OVERRIDES.get(parent['name'], {}).get(method)
            if typed is not None:
                return typed
            body = parent['method_bodies'].get(method)
            if body:
                return infer_method_signature(method, body)
            ancestor = parent['parent']
        return None

    ordered: list[str] = []
    pending = set(by_name)
    while pending:
        ready = sorted(name for name in pending if parent_of(by_name[name][1]) not in pending)
        if not ready:
            ready = [sorted(pending)[0]]
        for name in ready:
            pending.remove(name)
            ordered.append(name)
    for name in ordered:
        _, desc = by_name[name]
        base = luau_types.get(desc['parent'])
        luau_name = luau_types[by_name[name][0]]
        if not desc['registered']:
            output.append('--- Internal/abstract Kinemium base type; not directly constructible.')
        elif name == 'GPUCompute':
            output.append('--- Native GPU compute API. Use `Instance.new("GPUCompute")` to create an instance.')
        output.append(f'declare extern type {luau_name}' + (f' extends {base}' if base else '') + ' with')
        for field, typ in sorted(desc['props'].items()):
            if not IDENT.fullmatch(field) or field in desc['methods'] or field in desc['events']:
                continue
            output.append(f'    {field}: {PROPERTY_OVERRIDES.get(name, {}).get(field, typ)}')
        for field in sorted(desc['events']):
            if IDENT.fullmatch(field):
                output.append(f'    {field}: RBXScriptSignal')
        for field in sorted(desc['methods']):
            if not IDENT.fullmatch(field):
                continue
            if field == 'GetService' and name == 'DataModel' and not studio:
                for service in services:
                    output.append(f'    function GetService(self, serviceName: "{service}"): {service}')
            override = (CLASS_METHOD_OVERRIDES.get(name, {}).get(field)
                        or MORE_CLASS_METHODS.get(name, {}).get(field))
            body = desc['method_bodies'].get(field, '')
            inferred = infer_method_signature(field, body)
            sig = override or ((inherited_signature(desc, field) if not body else None) or inferred)
            ret = sig.returns
            if ret == 'any':
                ret = SPECIAL_METHODS.get(name, {}).get(field, 'any')
            if sig.description:
                output.append(f'    --- {sig.description}')
            args = ', ' + sig.params if sig.params else ''
            output.append(f'    function {field}(self{args}): {ret}')
        output.extend(['end', ''])

    for name, data in sorted(datatypes.items()):
        # Engine bindings use userdata; preserve exact registered type names.
        if name in luau_types.values() or name in ('Enum', 'EnumItem'):
            continue
        output.append(f'declare extern type {name} with')
        members = {**data['members'], **DATATYPE_MEMBERS.get(name, {})}
        for member, typ in sorted(members.items()):
            if IDENT.fullmatch(member) and member not in data['methods']:
                output.append(f'    {member}: {typ}')
        for method in sorted(data['methods']):
            if IDENT.fullmatch(method):
                signature = DATATYPE_METHOD_OVERRIDES.get(name, {}).get(method)
                if signature is None:
                    signature = Signature('...: any')
                if signature.description:
                    output.append(f'    --- {signature.description}')
                args = ', ' + signature.params if signature.params else ''
                output.append(f'    function {method}(self{args}): {signature.returns}')
        output.extend(['end', ''])
        funcs = data['functions']
        fields = data['fields']
        if not funcs and not fields:
            continue
        output.append(f'declare {name}: {{')
        for fname in sorted(funcs):
            signature = CONSTRUCTORS.get(name) if fname == 'new' else None
            if signature is None:
                inferred = STATIC_DATATYPE_OVERRIDES.get(name, {}).get(fname)
                if inferred is None:
                    inferred = infer_method_signature(fname, data['function_bodies'].get(fname, ''), first_index=1)
                signature = '(' + (inferred.params or '') + f') -> {name}' if inferred.params != '...: any' else f'(...any) -> {name}'
            output.append(f'    {fname}: {signature},')
        for field in sorted(fields - funcs):
            if IDENT.fullmatch(field):
                output.append(f'    {field}: {name},')
        output.extend(['}', ''])

    # In Luau's current checker, a broad `string -> Instance` fallback makes
    # *every* literal class constructor infer `any`, masking all method type
    # checks. Instead the fallback accepts a union of the *remaining known*
    # constructible class names, which cannot overlap specialized literals.
    # A dynamically computed string may require a user cast. Avoid >7 separate
    # intersections: Luau refuses to load overly-complex type declarations.
    common = ['GPUCompute', 'Part2D', 'World2D', 'Part', 'Folder', 'Frame', 'Model']
    specialized = [name for name in common if name in creatable]
    signatures = [f'((className: "{name}", parent: Instance?) -> {name})'
                  for name in specialized]
    remaining = [name for name in creatable if name not in specialized]
    if remaining:
        string_union = ' | '.join(f'"{name}"' for name in remaining)
        signatures.append(f'((className: {string_union}, parent: Instance?) -> Instance)')
    if studio:
        signatures = ['((className: string, parent: Instance?) -> Instance)']
    output.extend(['declare Instance: {', '    new: ' + ' &\n        '.join(signatures) + ',', '}', ''])
    if 'DataModel' in by_name:
        output.append('declare game: DataModel')
    elif 'ServiceProvider' in by_name:
        output.append('declare game: ServiceProvider')
    if 'Workspace' in by_name:
        output.append('declare workspace: Workspace')
    output.extend(['declare script: any' if studio else 'declare script: Instance', 'declare plugin: Instance',
                   'declare shared: {[any]: any}',
                   'declare _KINEMIUM_VERSION: string',
                   'declare _RUNTIME: {name: string, version: {display: string}, url: string?}',
                   'declare _LUAU: {version: {display: string, major: number, minor: number}, url: string?}',
                   'declare function tick(): number', 'declare function time(): number',
                   'declare function version(): string',
                   ''])
    if studio:
        output.extend([
            'export type KinemiumScriptSignal<T... = ...any> = RBXScriptSignal<T...>',
            'export type KinemiumConnection = RBXScriptConnection',
        ])
    return '\n'.join(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine-root', type=Path, default=ROOT / 'src' / 'engine')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--studio-header', action='store_true')
    parser.add_argument('--check', action='store_true', help='Verify output is current, do not rewrite')
    args = parser.parse_args()
    text = render(collect_classes(args.engine_root), collect_datatypes(args.engine_root), collect_enums(args.engine_root), studio=args.studio_header)
    if args.studio_header:
        metadata = json.loads(text.splitlines()[2].removeprefix('--#METADATA#'))
        arrays = '\n'.join('static constexpr std::string_view ' + key + '[] = {' + ', '.join(json.dumps(name) for name in values) + '};' for key, values in metadata.items())
        chunks = [text[i:i + 12000] for i in range(0, len(text), 12000)]
        text = 'static const std::string_view KinemiumDefinitionChunks[] = {\n' + ',\n'.join('R"KINEDEFS(' + chunk + ')KINEDEFS"' for chunk in chunks) + '\n};\n' + arrays + '\n'
    if args.check:
        if not args.output.exists() or args.output.read_text(encoding='utf-8') != text:
            parser.error(f'{args.output} is stale; regenerate it')
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    print(f'{args.output}: {len(text.splitlines())} lines, {len(text):,} bytes')


if __name__ == '__main__':
    main()

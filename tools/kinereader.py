#!/usr/bin/env python3
"""
kine.py - browse Kinemium .kine save files.

Reads format versions 2 through 8 (see serializer.odin) and lets you walk the
DataModel tree, read instance properties and attributes, search, inspect the
embedded asset table and terrain section, extract assets, and export JSON.

Usage
-----
  kine.py MAP.kine                       interactive shell
  kine.py MAP.kine info                  header summary
  kine.py MAP.kine tree [PATH] [-d N]    print the hierarchy
  kine.py MAP.kine props PATH [-f GLOB]  properties + attributes of an object
  kine.py MAP.kine get PATH PROP         one property value
  kine.py MAP.kine find [--class GLOB] [--name GLOB] [--prop NAME[=TEXT]]
  kine.py MAP.kine assets                embedded asset table
  kine.py MAP.kine extract ID OUT        write an embedded asset to disk
  kine.py MAP.kine terrain [--cells N]   terrain settings / cells
  kine.py MAP.kine export [PATH] [-o F]  JSON dump of a subtree
  kine.py MAP.kine syncback OUT [PATH]   Rojo-style project folder + sourcemap.json
  kine.py MAP.kine sourcemap [PATH]      print the sourcemap.json syncback would write

PATH syntax: Workspace/Model/Part  (leading "game" or the root's name is
optional). Duplicate names: Part[2] (1-based). Preorder index: #12 (root = #1).
In the shell, ".." and relative paths work too.
"""

import argparse
import cmd
import fnmatch
import json
import math
import os
import re
import shlex
import struct
import sys

sys.setrecursionlimit(20000)

MAGIC = b"KINE"
MIN_VERSION, MAX_VERSION = 2, 8
MAX_STRING = 16 * 1024 * 1024
MAX_FONT_BYTES = 32 * 1024 * 1024
TERRAIN_CELL_BYTES = 17

TAG_NIL, TAG_BOOL, TAG_NUMBER, TAG_INTEGER, TAG_STRING = 0, 1, 2, 3, 4
TAG_VECTOR3, TAG_USERDATA, TAG_ENUM, TAG_EXTENSION, TAG_INSTANCE_REF = 5, 6, 7, 18, 19


class KineError(Exception):
    def __init__(self, msg, offset=None):
        self.offset = offset
        super().__init__(msg if offset is None else f"{msg} (at byte offset {offset})")


# ---------------------------------------------------------------------------
# Value types
# ---------------------------------------------------------------------------

class Datatype:
    """A Luau userdata datatype (Vector3, CFrame, Color3, ...)."""
    __slots__ = ("type", "fields")

    def __init__(self, type_name, fields):
        self.type = type_name
        self.fields = fields  # dict, ordered

    def __repr__(self):
        return f"{self.type}({', '.join(fmt(v) for v in self.fields.values())})"


class EnumItem:
    __slots__ = ("enum", "value")

    def __init__(self, enum, value):
        self.enum, self.value = enum, value

    def __repr__(self):
        return f"Enum.{self.enum}[{self.value}]"


class ExtensionValue:
    __slots__ = ("extension_id", "type_name", "wire_version", "payload")

    def __init__(self, extension_id, type_name, wire_version, payload):
        self.extension_id, self.type_name = extension_id, type_name
        self.wire_version, self.payload = wire_version, payload

    def __repr__(self):
        return (f"Extension<{self.extension_id}.{self.type_name} "
                f"wire {self.wire_version}, {len(self.payload)} bytes>")


class InstanceRef:
    """Reference to another instance by preorder index (1 = root, 0 = nil)."""
    __slots__ = ("index", "target")

    def __init__(self, index):
        self.index, self.target = index, None

    def __repr__(self):
        if self.index == 0:
            return "nil"
        if self.target is not None:
            return f"<ref #{self.index} {self.target.class_name} {self.target.path()}>"
        return f"<ref #{self.index}>"


def fmt(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return f"{v:.6g}"
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(fmt(x) for x in v) + "}"
    if isinstance(v, (bytes, bytearray)):
        return f"<{len(v)} bytes>"
    return repr(v)


def type_name(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, Datatype):
        return v.type
    if isinstance(v, EnumItem):
        return "EnumItem"
    if isinstance(v, InstanceRef):
        return "Instance"
    if isinstance(v, ExtensionValue):
        return v.type_name
    return type(v).__name__


def jsonable(v):
    if v is None or isinstance(v, (bool, int, str)):
        return v
    if isinstance(v, float):
        return v if math.isfinite(v) else str(v)
    if isinstance(v, (list, tuple)):
        return [jsonable(x) for x in v]
    if isinstance(v, (bytes, bytearray)):
        return {"$bytes": len(v)}
    if isinstance(v, Datatype):
        return {"$type": v.type, **{k: jsonable(x) for k, x in v.fields.items()}}
    if isinstance(v, EnumItem):
        return {"$enum": v.enum, "value": v.value}
    if isinstance(v, InstanceRef):
        return {"$ref": v.index, "path": v.target.path() if v.target else None}
    if isinstance(v, ExtensionValue):
        return {"$extension": f"{v.extension_id}.{v.type_name}",
                "wire_version": v.wire_version, "payload_bytes": len(v.payload)}
    return str(v)


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

class Instance:
    def __init__(self, class_name, name, archivable, unique_id, parent):
        self.class_name = class_name
        self.name = name
        self.archivable = archivable
        self.unique_id = unique_id  # (random, time, index)
        self.parent = parent
        self.index = 0  # preorder index, 1-based
        self.properties = {}
        self.attributes = {}
        self.tags = []
        self.children = []

    def path(self):
        parts, node = [], self
        while node is not None:
            parts.append(node.name)
            node = node.parent
        return "/".join(reversed(parts))

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()

    def find_child(self, name, nth=1):
        seen = 0
        for c in self.children:
            if c.name == name:
                seen += 1
                if seen == nth:
                    return c
        return None

    def to_json(self, depth=None):
        d = {
            "class": self.class_name,
            "name": self.name,
            "archivable": self.archivable,
            "unique_id": list(self.unique_id),
            "properties": {k: jsonable(v) for k, v in self.properties.items()},
            "attributes": {k: jsonable(v) for k, v in self.attributes.items()},
        }
        if depth is None or depth > 0:
            nd = None if depth is None else depth - 1
            d["children"] = [c.to_json(nd) for c in self.children]
        else:
            d["child_count"] = len(self.children)
        return d


class Asset:
    def __init__(self, id, path, kind, offset, length):
        self.id, self.path, self.kind = id, path, kind
        self.offset, self.length = offset, length


class Terrain:
    pass


# ---------------------------------------------------------------------------
# Binary reader
# ---------------------------------------------------------------------------

# id -> (name, struct format, field names, bool fields)
SIMPLE_DATATYPES = {
    0: ("Axes", "<BBB", ("X", "Y", "Z"), {"X", "Y", "Z"}),
    1: ("BrickColor", "<i", ("Number",), ()),
    2: ("CFrame", "<12f",
        ("x", "y", "z", "r00", "r01", "r02", "r10", "r11", "r12", "r20", "r21", "r22"), ()),
    3: ("Color3", "<3f", ("R", "G", "B"), ()),
    6: ("DateTime", "<d", ("UnixTimestampMillis",), ()),
    7: ("Faces", "<6B", ("Top", "Bottom", "Left", "Right", "Front", "Back"),
        {"Top", "Bottom", "Left", "Right", "Front", "Back"}),
    9: ("NumberRange", "<2f", ("Min", "Max"), ()),
    12: ("PhysicalProperties", "<5f",
         ("Density", "Friction", "Elasticity", "FrictionWeight", "ElasticityWeight"), ()),
    13: ("Quaternion", "<4f", ("X", "Y", "Z", "W"), ()),
    14: ("Region3", "<6f", ("MinX", "MinY", "MinZ", "MaxX", "MaxY", "MaxZ"), ()),
    15: ("Region3int16", "<6h", ("MinX", "MinY", "MinZ", "MaxX", "MaxY", "MaxZ"), ()),
    16: ("SecurityCapabilities", "<QQ", ("bits_low", "bits_high"), ()),
    17: ("TweenInfo", "<fqqiBf",
         ("Time", "EasingStyle", "EasingDirection", "RepeatCount", "Reverses", "DelayTime"),
         {"Reverses"}),
    18: ("UDim", "<2f", ("Scale", "Offset"), ()),
    19: ("UDim2", "<4f", ("X_Scale", "X_Offset", "Y_Scale", "Y_Offset"), ()),
    20: ("UniqueId", "<qII", ("Random", "Time", "Index"), ()),
    21: ("Vector2", "<2f", ("X", "Y"), ()),
    22: ("Vector2int16", "<2h", ("X", "Y"), ()),
    23: ("Vector3", "<3f", ("x", "y", "z"), ()),
    24: ("Vector3int16", "<3h", ("X", "Y", "Z"), ()),
    25: ("Rect", "<4f", ("MinX", "MinY", "MaxX", "MaxY"), ()),
}
DT_COLOR_SEQUENCE, DT_CONTENT, DT_FONT, DT_NUMBER_SEQUENCE, DT_PATH_WAYPOINT = 4, 5, 8, 10, 11


class Reader:
    def __init__(self, data):
        self.data = data
        self.pos = 0
        self.version = 0

    def take(self, n):
        if n < 0 or self.pos + n > len(self.data):
            raise KineError(
                f"stream ended while reading {n} byte(s); only {len(self.data) - self.pos} remain",
                self.pos)
        b = self.data[self.pos:self.pos + n]
        self.pos += n
        return b

    def unpack(self, f):
        size = struct.calcsize(f)
        if self.pos + size > len(self.data):
            raise KineError(f"stream ended while reading {size} byte(s)", self.pos)
        v = struct.unpack_from(f, self.data, self.pos)
        self.pos += size
        return v

    def u8(self): return self.unpack("<B")[0]
    def u16(self): return self.unpack("<H")[0]
    def u32(self): return self.unpack("<I")[0]
    def i32(self): return self.unpack("<i")[0]
    def i64(self): return self.unpack("<q")[0]
    def f32(self): return self.unpack("<f")[0]
    def f64(self): return self.unpack("<d")[0]

    def varuint(self):
        value = 0
        for shift in range(0, 35, 7):
            b = self.u8()
            if shift == 28 and b > 0x0F:
                raise KineError("varuint is longer than 32 bits", self.pos - 1)
            value |= (b & 0x7F) << shift
            if not b & 0x80:
                return value
        raise KineError("varuint did not terminate within 5 bytes", self.pos)

    def string(self):
        at = self.pos
        n = self.varuint()
        if n > MAX_STRING:
            raise KineError(f"string declares {n} bytes, over the {MAX_STRING} limit", at)
        if n > len(self.data) - self.pos:
            raise KineError(
                f"string declares {n} bytes but only {len(self.data) - self.pos} remain", at)
        return self.take(n).decode("utf-8", errors="replace")


class KineFile:
    def __init__(self, data, source="<memory>"):
        self.source = source
        self.size = len(data)
        self.data = data
        self.assets = []
        self.assets_by_id = {}
        self.root = None
        self.all = []  # preorder instances
        self.terrain = None
        self.version = 0
        self.terrain_present = False
        self._parse()

    @classmethod
    def open(cls, path):
        with open(path, "rb") as f:
            return cls(f.read(), path)

    # -- parsing -----------------------------------------------------------

    def _parse(self):
        r = Reader(self.data)
        if len(self.data) < 5:
            raise KineError(f"need at least 5 bytes, file is {len(self.data)}", 0)
        if r.take(4) != MAGIC:
            raise KineError("bad magic: this is not a .kine file", 0)
        self.version = r.version = r.u8()
        if not MIN_VERSION <= self.version <= MAX_VERSION:
            raise KineError(
                f"file is version {self.version}; this tool reads {MIN_VERSION}-{MAX_VERSION}", 4)
        if self.version >= 3:
            self._read_assets(r)
        self.root = self._read_instance(r, None)
        if self.version >= 4:
            self._read_terrain(r)
        if r.pos != len(self.data):
            raise KineError(f"{len(self.data) - r.pos} trailing byte(s) after last record", r.pos)
        for i, inst in enumerate(self.all, 1):
            inst.index = i
        if self.version >= 8:
            for inst in self.all:
                for v in inst.properties.values():
                    if isinstance(v, InstanceRef) and v.index:
                        if v.index > len(self.all):
                            raise KineError(f"instance reference #{v.index} is outside the tree")
                        v.target = self.all[v.index - 1]

    def _read_assets(self, r):
        count = r.u32()
        for i in range(count):
            aid = r.string()
            path = r.string()
            kind = r.u8()
            length = r.varuint()
            offset = r.pos
            r.take(length)  # skip; bytes are sliced lazily
            a = Asset(aid, path, kind, offset, length)
            self.assets.append(a)
            self.assets_by_id[aid] = a

    def asset_bytes(self, asset):
        return bytes(self.data[asset.offset:asset.offset + asset.length])

    def _read_instance(self, r, parent):
        cls = r.string()
        name = r.string()
        archivable = bool(r.u8())
        uid = (r.i64(), r.u32(), r.u32())
        inst = Instance(cls, name, archivable, uid, parent)
        self.all.append(inst)
        if parent is not None:
            parent.children.append(inst)
        try:
            for _ in range(r.u32()):
                key = r.string()
                value = self._read_value(r)
                if key == "Tags" and isinstance(value, str):
                    inst.tags.extend(tag for tag in value.split("\0") if tag)
                else:
                    inst.properties[key] = value
            for _ in range(r.u32()):
                key = r.string()
                inst.attributes[key] = self._read_value(r)
            n = r.u32()
            if n > len(r.data) - r.pos:
                raise KineError(f"child count {n} exceeds remaining bytes", r.pos)
            for _ in range(n):
                self._read_instance(r, inst)
        except KineError as e:
            raise KineError(f"in {cls} {name!r}: {e}") from None
        return inst

    def _read_value(self, r):
        tag = r.u8()
        if tag == TAG_NIL:
            return None
        if tag == TAG_BOOL:
            return r.u8() != 0
        if tag == TAG_NUMBER:
            return r.f64()
        if tag == TAG_INTEGER:
            return r.i64()
        if tag == TAG_STRING:
            return r.string()
        if tag == TAG_VECTOR3:
            return Datatype("Vector3", dict(zip("xyz", r.unpack("<3f"))))
        if tag == TAG_USERDATA:
            return self._read_datatype(r, r.u16())
        if tag == TAG_ENUM:
            return EnumItem(r.string(), r.i64())
        if tag == TAG_EXTENSION:
            ext, tname, wire, size = r.string(), r.string(), r.u32(), r.varuint()
            if size > MAX_STRING:
                raise KineError("extension payload too large", r.pos)
            return ExtensionValue(ext, tname, wire, r.take(size))
        if tag == TAG_INSTANCE_REF:
            return InstanceRef(r.u32())
        raise KineError(f"unknown value tag {tag}", r.pos - 1)

    def _read_datatype(self, r, dt):
        if dt in SIMPLE_DATATYPES:
            name, f, names, bools = SIMPLE_DATATYPES[dt]
            vals = r.unpack(f)
            return Datatype(name, {n: (bool(v) if n in bools else v) for n, v in zip(names, vals)})
        if dt == DT_COLOR_SEQUENCE:
            n = r.u32()
            if n > len(r.data):
                raise KineError("colour sequence keypoint count is bogus", r.pos)
            kps = [r.unpack("<4f") for _ in range(n)]
            return Datatype("ColorSequence", {"Keypoints": [(t, (R, G, B)) for t, R, G, B in kps]})
        if dt == DT_NUMBER_SEQUENCE:
            n = r.u32()
            if n > len(r.data):
                raise KineError("number sequence keypoint count is bogus", r.pos)
            return Datatype("NumberSequence", {"Keypoints": [r.unpack("<3f") for _ in range(n)]})
        if dt == DT_CONTENT:
            f = {"uri": r.string()}
            if r.version >= 3:
                f["object_id"] = r.u32()
                f["object_kind"] = r.u8()
            return Datatype("Content", f)
        if dt == DT_FONT:
            f = {"Family": r.string(), "Weight": r.i64(), "Style": r.i64()}
            if r.version >= 5 and r.u8():
                n = r.varuint()
                if n > MAX_FONT_BYTES:
                    raise KineError(f"font declares {n} face bytes, over the limit", r.pos)
                f["Data"] = r.take(n)
            return Datatype("Font", f)
        if dt == DT_PATH_WAYPOINT:
            x, y, z = r.unpack("<3f")
            return Datatype("PathWaypoint",
                            {"Position": (x, y, z), "Action": r.i64(), "Label": r.string()})
        raise KineError(f"unknown datatype id {dt}", r.pos)

    def _read_terrain(self, r):
        if r.u8() == 0:
            return
        self.terrain_present = True
        t = Terrain()
        t.decoration = bool(r.u8())
        (t.voxel_size, t.iso_level, t.grass_length, t.water_reflectance,
         t.water_transparency, t.water_wave_size, t.water_wave_speed,
         wr, wg, wb) = r.unpack("<10f")
        t.water_color = (wr, wg, wb)
        t.material_variant = r.string() if r.version >= 7 else ""
        t.material_colours = {}
        for _ in range(r.u32()):
            m = r.u32()
            t.material_colours[m] = r.unpack("<3f")
        count = r.u32()
        if count * TERRAIN_CELL_BYTES > len(r.data) - r.pos:
            raise KineError(f"terrain claims {count} cells but the stream is too short", r.pos)
        raw = r.take(count * TERRAIN_CELL_BYTES)
        t.cells = [(x, y, z, m, o / 65535.0, w / 65535.0)
                   for x, y, z, m, o, w in struct.iter_unpack("<iiiBHH", raw)]
        self.terrain = t

    # -- navigation --------------------------------------------------------

    def resolve(self, path, base=None):
        path = (path or "").strip()
        if base is None:
            base = self.root
        if path in ("", "/", "."):
            return self.root if path == "/" else base
        if path.startswith("#") and path[1:].isdigit():
            i = int(path[1:])
            if 1 <= i <= len(self.all):
                return self.all[i - 1]
            raise KineError(f"no instance #{i} (tree has {len(self.all)})")
        attempts = [path.split("/")]
        if "/" not in path and "." in path and not path.startswith(".."):
            attempts.append(path.split("."))
        for segs in attempts:
            node = self._walk_segments(segs, base, absolute=path.startswith("/"))
            if node is not None:
                return node
        raise KineError(f"no instance at path {path!r}")

    def _walk_segments(self, segs, base, absolute):
        node = self.root if absolute else base
        segs = [s for s in segs if s != ""]
        for i, seg in enumerate(segs):
            if seg == ".":
                continue
            if seg == "..":
                node = node.parent or node
                continue
            nxt = self._child(node, seg)
            if nxt is None and i == 0 and (seg == "game" or seg == self.root.name):
                continue  # optional leading root name
            if nxt is None:
                return None
            node = nxt
        return node

    @staticmethod
    def _child(node, seg):
        c = node.find_child(seg)
        if c is not None:
            return c
        m = re.match(r"^(.*)\[(\d+)\]$", seg)
        if m:
            return node.find_child(m.group(1), int(m.group(2)))
        return None


# ---------------------------------------------------------------------------
# Commands (shared by CLI and shell)
# ---------------------------------------------------------------------------

def do_info(doc, out):
    kinds = {}
    for i in doc.all:
        kinds[i.class_name] = kinds.get(i.class_name, 0) + 1
    print(f"file:       {doc.source}", file=out)
    print(f"size:       {doc.size:,} bytes", file=out)
    print(f"version:    {doc.version}", file=out)
    print(f"root:       {doc.root.class_name} {doc.root.name!r}", file=out)
    print(f"instances:  {len(doc.all):,}", file=out)
    print(f"assets:     {len(doc.assets)} ({sum(a.length for a in doc.assets):,} bytes)", file=out)
    t = doc.terrain
    print(f"terrain:    {f'{len(t.cells):,} cells' if t else 'none'}", file=out)
    print("top classes:", file=out)
    for k, n in sorted(kinds.items(), key=lambda kv: -kv[1])[:15]:
        print(f"  {n:>8,}  {k}", file=out)


def do_tree(doc, node, depth, out, show_index=False):
    def rec(n, prefix, last, level):
        label = f"{n.name} [{n.class_name}]"
        if show_index:
            label += f" #{n.index}"
        if level == 0:
            print(label, file=out)
            child_prefix = ""
        else:
            print(prefix + ("└─ " if last else "├─ ") + label, file=out)
            child_prefix = prefix + ("   " if last else "│  ")
        if depth is not None and level >= depth:
            if n.children:
                print(child_prefix + f"└─ … {len(n.children)} child(ren)", file=out)
            return
        for i, c in enumerate(n.children):
            rec(c, child_prefix, i == len(n.children) - 1, level + 1)
    rec(node, "", True, 0)


def do_props(doc, node, pattern, out, as_json=False):
    props = {k: v for k, v in node.properties.items()
             if not pattern or fnmatch.fnmatch(k.lower(), pattern.lower())}
    attrs = {k: v for k, v in node.attributes.items()
             if not pattern or fnmatch.fnmatch(k.lower(), pattern.lower())}
    if as_json:
        print(json.dumps({"class": node.class_name, "name": node.name,
                          "properties": {k: jsonable(v) for k, v in props.items()},
                          "attributes": {k: jsonable(v) for k, v in attrs.items()},
                          "tags": node.tags},
                         indent=2), file=out)
        return
    print(f"{node.class_name} {node.name!r}  (#{node.index}, archivable={node.archivable}, "
          f"children={len(node.children)})", file=out)
    print(f"path:      {node.path()}", file=out)
    print(f"unique id: {node.unique_id[0]:x}-{node.unique_id[1]:x}-{node.unique_id[2]:x}", file=out)
    if node.tags:
        print(f"tags:      {', '.join(node.tags)}", file=out)
    width = max([len(k) for k in list(props) + list(attrs)] + [8])
    print(f"\nProperties ({len(props)}):", file=out)
    for k in sorted(props):
        v = props[k]
        print(f"  {k:<{width}}  {type_name(v):<18} {fmt(v)}", file=out)
        note = asset_note(doc, v)
        if note:
            print(f"  {'':<{width}}  {'':<18} ↳ {note}", file=out)
    if attrs:
        print(f"\nAttributes ({len(attrs)}):", file=out)
        for k in sorted(attrs):
            print(f"  {k:<{width}}  {type_name(attrs[k]):<18} {fmt(attrs[k])}", file=out)


def asset_note(doc, v):
    uri = v.fields.get("uri") if isinstance(v, Datatype) else v if isinstance(v, str) else None
    if isinstance(uri, str) and uri.startswith("kineasset://"):
        a = doc.assets_by_id.get(uri[len("kineasset://"):])
        if a:
            return f"embedded asset: {a.path!r}, kind {a.kind}, {a.length:,} bytes"
        return "embedded asset reference (not found in table)"
    return None


def do_get(doc, node, prop, out):
    if prop in node.properties:
        v = node.properties[prop]
    elif prop in node.attributes:
        v = node.attributes[prop]
    else:
        raise KineError(f"{node.class_name} {node.name!r} has no property or attribute {prop!r}")
    print(fmt(v), file=out)
    note = asset_note(doc, v)
    if note:
        print(f"  ↳ {note}", file=out)


def do_find(doc, root, cls, name, prop, out, limit=None):
    prop_name, _, prop_text = (prop or "").partition("=")
    n = 0
    for inst in root.walk():
        if cls and not fnmatch.fnmatch(inst.class_name.lower(), cls.lower()):
            continue
        if name and not fnmatch.fnmatch(inst.name.lower(), name.lower()):
            continue
        if prop:
            hit = False
            for src in (inst.properties, inst.attributes):
                if prop_name in src and (not prop_text or prop_text.lower() in fmt(src[prop_name]).lower()):
                    hit = True
            if not hit:
                continue
        print(f"#{inst.index:<6} {inst.class_name:<22} {inst.path()}", file=out)
        n += 1
        if limit and n >= limit:
            print(f"… stopped at {limit} results", file=out)
            break
    print(f"{n} match(es)", file=out)


KIND_NAMES = {}  # unknown enum order in the source, so kinds print as numbers


def do_assets(doc, out):
    if not doc.assets:
        print("no embedded assets", file=out)
        return
    for a in doc.assets:
        print(f"{a.id}  kind={KIND_NAMES.get(a.kind, a.kind)}  {a.length:>10,} B  {a.path}", file=out)


def do_extract(doc, ident, dest, out):
    ident = ident[len("kineasset://"):] if ident.startswith("kineasset://") else ident
    matches = [a for a in doc.assets if a.id == ident] or [a for a in doc.assets if a.id.startswith(ident)]
    if len(matches) != 1:
        raise KineError(f"{'no' if not matches else 'multiple'} asset matches {ident!r}")
    with open(dest, "wb") as f:
        f.write(doc.asset_bytes(matches[0]))
    print(f"wrote {matches[0].length:,} bytes to {dest}", file=out)


def do_terrain(doc, cells, out):
    t = doc.terrain
    if not t:
        print("no terrain in this map", file=out)
        return
    print(f"voxel size:          {t.voxel_size:g}", file=out)
    print(f"iso level:           {t.iso_level:g}", file=out)
    print(f"decoration:          {t.decoration}", file=out)
    print(f"grass length:        {t.grass_length:g}", file=out)
    print(f"water color:         {fmt(Datatype('Color3', dict(zip('RGB', t.water_color))))}", file=out)
    print(f"water reflectance:   {t.water_reflectance:g}", file=out)
    print(f"water transparency:  {t.water_transparency:g}", file=out)
    print(f"water wave size/spd: {t.water_wave_size:g} / {t.water_wave_speed:g}", file=out)
    if doc.version >= 7:
        print(f"material variant:    {t.material_variant!r}", file=out)
    print(f"material colours:    {len(t.material_colours)}", file=out)
    for m, c in sorted(t.material_colours.items()):
        print(f"  material {m}: ({c[0]:.3f}, {c[1]:.3f}, {c[2]:.3f})", file=out)
    print(f"cells:               {len(t.cells):,}", file=out)
    mats = {}
    for c in t.cells:
        mats[c[3]] = mats.get(c[3], 0) + 1
    for m, n in sorted(mats.items()):
        print(f"  material {m}: {n:,} cells", file=out)
    if t.cells:
        xs, ys, zs = zip(*[(c[0], c[1], c[2]) for c in t.cells])
        print(f"bounds (voxels):     x {min(xs)}..{max(xs)}  y {min(ys)}..{max(ys)}  z {min(zs)}..{max(zs)}", file=out)
    for c in t.cells[:cells]:
        print(f"  ({c[0]}, {c[1]}, {c[2]}) mat={c[3]} occ={c[4]:.3f} water={c[5]:.3f}", file=out)


def do_export(doc, node, dest, depth, out):
    text = json.dumps(node.to_json(depth), indent=2, ensure_ascii=False)
    if dest:
        with open(dest, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"wrote {len(text):,} chars to {dest}", file=out)
    else:
        print(text, file=out)


# ---------------------------------------------------------------------------
# Rojo-style syncback
# ---------------------------------------------------------------------------
#
# Layout written (mirrors `rojo syncback`):
#   default.project.json      tree: root class + one $path per top-level child
#   sourcemap.json            Rojo sourcemap (name/className/filePaths/children)
#   src/...                   Script        -> Name.server.luau
#                             LocalScript   -> Name.client.luau
#                             ModuleScript  -> Name.luau
#                             with children -> Name/init.<ext> + children inside
#                             Folder        -> plain directory
#                             other classes -> directory + init.meta.json, or a
#                                              leaf Name.model.json
#                             extra props   -> Name.meta.json beside scripts
#   assets/                   embedded assets + manifest.json
#   terrain.json, terrain.cells.json
#   kine-extra.json           values Rojo has no type for (Region3, Quaternion,
#                             instance refs, extension types, ...), keyed by #index

SCRIPT_EXT = {"Script": ".server.luau", "LocalScript": ".client.luau", "ModuleScript": ".luau"}
_INVALID_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_RESERVED = ({"con", "prn", "aux", "nul"} | {f"com{i}" for i in range(1, 10)}
             | {f"lpt{i}" for i in range(1, 10)})


def safe_filename(name):
    s = _INVALID_CHARS.sub("_", name).rstrip(" .")[:120]
    if not s:
        s = "_"
    if s.split(".")[0].lower() in _RESERVED or s.lower() == "init":
        s += "_"
    return s


def _n(x):
    """f32 values come back with binary noise (0.1 -> 0.10000000149); trim it."""
    return float(f"{x:.7g}") if isinstance(x, float) else x


def rojo_value(v):
    """Convert a decoded value to Rojo's explicit typed JSON, or None if Rojo has no type."""
    if isinstance(v, bool):
        return {"Bool": v}
    if isinstance(v, int):
        return {"Int64": v}
    if isinstance(v, float):
        return {"Float64": v}
    if isinstance(v, str):
        return {"String": v}
    if isinstance(v, EnumItem):
        return {"Enum": v.value}
    if not isinstance(v, Datatype):
        return None
    t, f = v.type, v.fields
    vals = [_n(x) for x in f.values()]
    if t in ("Vector3", "Vector2", "Vector3int16", "Vector2int16", "Color3",
             "UDim", "NumberRange"):
        return {t: vals}
    if t == "CFrame":
        return {"CFrame": {"position": vals[0:3],
                           "orientation": [vals[3:6], vals[6:9], vals[9:12]]}}
    if t == "UDim2":
        return {"UDim2": [vals[0:2], vals[2:4]]}
    if t == "BrickColor":
        return {"BrickColor": f["Number"]}
    if t in ("Faces", "Axes"):
        return {t: [k for k, on in f.items() if on]}
    if t == "NumberSequence":
        return {"NumberSequence": {"keypoints": [
            {"time": _n(a), "value": _n(b), "envelope": _n(c)} for a, b, c in f["Keypoints"]]}}
    if t == "ColorSequence":
        return {"ColorSequence": {"keypoints": [
            {"time": _n(a), "color": [_n(x) for x in rgb]} for a, rgb in f["Keypoints"]]}}
    if t == "Font" and "Data" not in f:
        return {"Font": {"family": f["Family"], "weight": f["Weight"], "style": f["Style"]}}
    if t == "Content" and not f.get("object_id"):
        return {"Content": f["uri"]}
    if t == "PhysicalProperties":
        return {"PhysicalProperties": {
            "density": vals[0], "friction": vals[1], "elasticity": vals[2],
            "frictionWeight": vals[3], "elasticityWeight": vals[4]}}
    return None


def _valid_json(val):
    try:
        json.dumps(val, allow_nan=False)
        return True
    except ValueError:
        return False


class Syncback:
    def __init__(self, doc, out, src="src", collapse=False, scripts_only=False,
                 extra=True, dry=False):
        self.doc, self.out, self.src = doc, out, src
        self.collapse, self.scripts_only, self.extra_on, self.dry = collapse, scripts_only, extra, dry
        self.extra = {}
        self.stats = {"scripts": 0, "meta": 0, "models": 0, "dirs": 0, "extra_values": 0}
        self.has_scripts = {}
        self.warnings = []

    # -- file helpers ------------------------------------------------------

    def _mkdir(self, path):
        if not self.dry:
            os.makedirs(path, exist_ok=True)

    def _write(self, path, data):
        if self.dry:
            return
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        if isinstance(data, str):
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(data)
        else:
            with open(path, "wb") as f:
                f.write(data)

    def _write_json(self, path, obj, indent=2):
        text = json.dumps(obj, indent=indent, ensure_ascii=False, allow_nan=False,
                          separators=None if indent else (",", ":"))
        self._write(path, text + "\n")

    @staticmethod
    def _unique(used, stem):
        base, n = stem, 2
        while stem.lower() in used:
            stem = f"{base}~{n}"
            n += 1
        used.add(stem.lower())
        return stem

    # -- member conversion ---------------------------------------------------

    def members(self, inst, skip=()):
        props, attrs, extra_p, extra_a = {}, {}, {}, {}
        for src, dst, ex in ((inst.properties, props, extra_p), (inst.attributes, attrs, extra_a)):
            for k, v in src.items():
                if k in skip or v is None:
                    continue
                val = rojo_value(v)
                if val is not None and _valid_json(val):
                    dst[k] = val
                else:
                    ex[k] = jsonable(v)
        if extra_p or extra_a:
            self.stats["extra_values"] += len(extra_p) + len(extra_a)
            rec = {"path": inst.path(), "class": inst.class_name}
            if extra_p:
                rec["properties"] = extra_p
            if extra_a:
                rec["attributes"] = extra_a
            self.extra[f"#{inst.index}"] = rec
        return props, attrs

    @staticmethod
    def _meta(override, class_name, props, attrs):
        m = {}
        if override:
            m["name"] = override
        if class_name:
            m["className"] = class_name
        if props:
            m["properties"] = props
        if attrs:
            m["attributes"] = attrs
        return m

    # -- emission ------------------------------------------------------------

    def model_dict(self, inst, name):
        props, attrs = self.members(inst)
        d = self._meta(name, inst.class_name, props, attrs)
        if inst.children:
            d["children"] = [self.model_dict(c, c.name) for c in inst.children]
        return d

    def model_sm(self, inst, files):
        n = {"name": inst.name, "className": inst.class_name, "filePaths": files}
        if inst.children:
            n["children"] = [self.model_sm(c, files) for c in inst.children]
        return n

    def emit_children(self, inst, d_abs, d_rel, sm):
        used, kids = set(), []
        for c in inst.children:
            node, _ = self.emit(c, d_abs, d_rel, used)
            kids.append(node)
        if kids:
            sm["children"] = kids

    def emit(self, inst, dir_abs, dir_rel, used):
        cls = inst.class_name
        stem = self._unique(used, safe_filename(inst.name))
        override = inst.name if stem != inst.name else None
        is_script = cls in SCRIPT_EXT
        as_model = not is_script and (
            (self.collapse and not self.has_scripts[inst]) or (not inst.children and cls != "Folder"))
        props, attrs = ({}, {}) if as_model else self.members(inst, ("Source",) if is_script else ())
        rel = lambda *p: "/".join([dir_rel, *p])
        sm = {"name": inst.name, "className": cls}

        if is_script:
            ext = SCRIPT_EXT[cls]
            source = inst.properties.get("Source")
            source = source if isinstance(source, str) else ""
            self.stats["scripts"] += 1
            if inst.children:
                d = os.path.join(dir_abs, stem)
                self._mkdir(d)
                self._write(os.path.join(d, "init" + ext), source)
                files = [rel(stem, "init" + ext)]
                primary = rel(stem)
                meta = self._meta(override, None, props, attrs)
                if meta:
                    self._write_json(os.path.join(d, "init.meta.json"), meta)
                    files.append(rel(stem, "init.meta.json"))
                    self.stats["meta"] += 1
                sm["filePaths"] = files
                self.emit_children(inst, d, rel(stem), sm)
            else:
                self._write(os.path.join(dir_abs, stem + ext), source)
                files = [rel(stem + ext)]
                primary = files[0]
                meta = self._meta(override, None, props, attrs)
                if meta:
                    self._write_json(os.path.join(dir_abs, stem + ".meta.json"), meta)
                    files.append(rel(stem + ".meta.json"))
                    self.stats["meta"] += 1
                sm["filePaths"] = files
            return sm, primary

        if as_model:
            model = self.model_dict(inst, override)
            self._write_json(os.path.join(dir_abs, stem + ".model.json"), model)
            self.stats["models"] += 1
            file = rel(stem + ".model.json")
            return self.model_sm(inst, [file]), file

        d = os.path.join(dir_abs, stem)
        self._mkdir(d)
        self.stats["dirs"] += 1
        meta = self._meta(override, cls if cls != "Folder" else None, props, attrs)
        if not meta and not inst.children:
            meta = {"className": "Folder"}  # keeps an empty folder in version control
        files = [rel(stem)]
        if meta:
            self._write_json(os.path.join(d, "init.meta.json"), meta)
            files.append(rel(stem, "init.meta.json"))
            self.stats["meta"] += 1
        sm["filePaths"] = files
        self.emit_children(inst, d, rel(stem), sm)
        return sm, rel(stem)

    # -- driver ----------------------------------------------------------------

    def run(self, root):
        if not self.dry:
            if os.path.isdir(self.out) and os.listdir(self.out):
                pass  # caller decides whether that is allowed (see do_syncback)
            os.makedirs(self.out, exist_ok=True)
        nodes = list(root.walk())
        for inst in reversed(nodes):  # children are visited before their parents
            self.has_scripts[inst] = inst.class_name in SCRIPT_EXT or any(
                self.has_scripts[c] for c in inst.children)

        src_abs = os.path.join(self.out, self.src)
        self._mkdir(src_abs)
        used, children_sm, project_children = set(), [], {}
        for child in root.children:
            node, primary = self.emit(child, src_abs, self.src, used)
            children_sm.append(node)
            key, n = child.name, 2
            while key in project_children:
                key = f"{child.name}~{n}"
                n += 1
                self.warnings.append(f"duplicate top-level name {child.name!r}; project key is {key!r}")
            project_children[key] = {"$path": primary}

        props, attrs = self.members(root)
        tree = {"$className": root.class_name}
        if props:
            tree["$properties"] = props
        if attrs:
            tree["$attributes"] = attrs
        tree.update(project_children)
        self._write_json(os.path.join(self.out, "default.project.json"),
                         {"name": root.name, "tree": tree})

        sourcemap = {"name": root.name, "className": root.class_name,
                     "filePaths": ["default.project.json"]}
        if children_sm:
            sourcemap["children"] = children_sm
        if self.scripts_only:
            sourcemap = self._prune(sourcemap, keep_root=True)
        self._write_json(os.path.join(self.out, "sourcemap.json"), sourcemap)
        self.sourcemap = sourcemap
        return sourcemap

    def _prune(self, node, keep_root=False):
        kids = [k for k in (self._prune(c) for c in node.get("children", [])) if k]
        if not keep_root and node["className"] not in SCRIPT_EXT and not kids:
            return None
        node = dict(node)
        node.pop("children", None)
        if kids:
            node["children"] = kids
        return node

    def write_assets(self):
        if not self.doc.assets:
            return 0
        used, manifest = set(), []
        for a in self.doc.assets:
            base = os.path.basename(a.path.replace("\\", "/")) or "asset"
            fname = self._unique(used, safe_filename(f"{a.id[:12]}_{base}"))
            self._write(os.path.join(self.out, "assets", fname), self.doc.asset_bytes(a))
            manifest.append({"id": a.id, "path": a.path, "kind": a.kind,
                             "bytes": a.length, "file": f"assets/{fname}"})
        self._write_json(os.path.join(self.out, "assets", "manifest.json"), manifest)
        return len(manifest)

    def write_terrain(self):
        t = self.doc.terrain
        if not t:
            return 0
        self._write_json(os.path.join(self.out, "terrain.json"), {
            "voxelSize": _n(t.voxel_size), "isoLevel": _n(t.iso_level),
            "decoration": t.decoration, "grassLength": _n(t.grass_length),
            "waterColor": [_n(x) for x in t.water_color],
            "waterReflectance": _n(t.water_reflectance),
            "waterTransparency": _n(t.water_transparency),
            "waterWaveSize": _n(t.water_wave_size), "waterWaveSpeed": _n(t.water_wave_speed),
            "materialVariant": t.material_variant,
            "materialColours": {str(m): [_n(x) for x in c] for m, c in sorted(t.material_colours.items())},
            "cellsFile": "terrain.cells.json", "cellFormat": ["x", "y", "z", "material", "occupancy", "water"],
        })
        self._write_json(os.path.join(self.out, "terrain.cells.json"),
                         [[x, y, z, m, round(o, 5), round(w, 5)] for x, y, z, m, o, w in t.cells],
                         indent=None)
        return len(t.cells)


def do_sourcemap(doc, node, collapse, scripts_only, out):
    sb = Syncback(doc, "", collapse=collapse, scripts_only=scripts_only, dry=True)
    print(json.dumps(sb.run(node), indent=2, ensure_ascii=False), file=out)


def do_syncback(doc, node, dest, out, src="src", collapse=False, scripts_only=False,
                force=False, extra=True, assets=True, terrain=True):
    if os.path.isdir(dest) and os.listdir(dest) and not force:
        raise KineError(f"{dest!r} is not empty; use --force to write into it "
                        "(existing files are overwritten, stale ones are not removed)")
    sb = Syncback(doc, dest, src, collapse, scripts_only, extra)
    sb.run(node)
    n_assets = sb.write_assets() if assets else 0
    n_cells = sb.write_terrain() if terrain and node is doc.root else 0
    if extra and sb.extra:
        sb._write_json(os.path.join(dest, "kine-extra.json"), sb.extra)
    s = sb.stats
    print(f"wrote {dest}", file=out)
    print(f"  {s['scripts']} script(s), {s['dirs']} directorie(s), {s['models']} .model.json, "
          f"{s['meta']} .meta.json", file=out)
    print(f"  default.project.json, sourcemap.json", file=out)
    if n_assets:
        print(f"  {n_assets} asset(s) in assets/", file=out)
    if n_cells:
        print(f"  terrain.json + terrain.cells.json ({n_cells:,} cells)", file=out)
    if s["extra_values"]:
        where = "kine-extra.json" if extra else "dropped (--no-extra)"
        print(f"  {s['extra_values']} value(s) with no Rojo type -> {where}", file=out)
    for w in sb.warnings:
        print(f"  warning: {w}", file=out)


# ---------------------------------------------------------------------------
# Interactive shell
# ---------------------------------------------------------------------------

class Shell(cmd.Cmd):
    def __init__(self, doc):
        super().__init__()
        self.doc = doc
        self.cwd = doc.root
        self._prompt()

    def _prompt(self):
        self.prompt = f"kine:{self.cwd.path()}> "

    def _run(self, fn, *a):
        try:
            fn(*a)
        except KineError as e:
            print(f"error: {e}")
        except OSError as e:
            print(f"error: {e}")

    def _node(self, arg):
        return self.doc.resolve(arg, self.cwd) if arg else self.cwd

    def do_info(self, arg):
        "info                  file summary"
        do_info(self.doc, sys.stdout)

    def do_ls(self, arg):
        "ls [PATH]             list children"
        def f():
            n = self._node(arg.strip())
            for c in n.children:
                extra = f"  ({len(c.children)})" if c.children else ""
                print(f"#{c.index:<6} {c.class_name:<22} {c.name}{extra}")
        self._run(f)

    def do_cd(self, arg):
        "cd PATH               change directory (.. and / work)"
        def f():
            self.cwd = self._node(arg.strip())
            self._prompt()
        self._run(f)

    def do_pwd(self, arg):
        "pwd                   show current path"
        print(self.cwd.path())

    def do_tree(self, arg):
        "tree [PATH] [DEPTH]   print hierarchy (default depth 3)"
        def f():
            parts = shlex.split(arg)
            depth = 3
            if parts and parts[-1].isdigit() and len(parts) > 1:
                depth = int(parts.pop())
            elif len(parts) == 1 and parts[0].isdigit():
                depth, parts = int(parts[0]), []
            do_tree(self.doc, self._node(parts[0] if parts else ""), depth, sys.stdout, True)
        self._run(f)

    def do_props(self, arg):
        "props [PATH] [-f GLOB]   properties and attributes"
        def f():
            parts = shlex.split(arg)
            pattern = None
            if "-f" in parts:
                i = parts.index("-f")
                pattern = parts[i + 1]
                del parts[i:i + 2]
            do_props(self.doc, self._node(parts[0] if parts else ""), pattern, sys.stdout)
        self._run(f)

    do_p = do_props

    def do_get(self, arg):
        "get PROP [PATH]       one property or attribute"
        def f():
            parts = shlex.split(arg)
            if not parts:
                raise KineError("usage: get PROP [PATH]")
            do_get(self.doc, self._node(parts[1] if len(parts) > 1 else ""), parts[0], sys.stdout)
        self._run(f)

    def do_find(self, arg):
        "find [--class GLOB] [--name GLOB] [--prop NAME[=TEXT]]   search under cwd"
        def f():
            p = argparse.ArgumentParser(prog="find", add_help=False)
            p.add_argument("--class", dest="cls")
            p.add_argument("--name")
            p.add_argument("--prop")
            ns = p.parse_args(shlex.split(arg))
            do_find(self.doc, self.cwd, ns.cls, ns.name, ns.prop, sys.stdout, 500)
        try:
            self._run(f)
        except SystemExit:
            pass

    def do_assets(self, arg):
        "assets                embedded asset table"
        do_assets(self.doc, sys.stdout)

    def do_extract(self, arg):
        "extract ID OUT        write an asset to a file"
        def f():
            parts = shlex.split(arg)
            if len(parts) != 2:
                raise KineError("usage: extract ID OUT")
            do_extract(self.doc, parts[0], parts[1], sys.stdout)
        self._run(f)

    def do_terrain(self, arg):
        "terrain [N]           terrain summary, plus first N cells"
        do_terrain(self.doc, int(arg) if arg.strip().isdigit() else 0, sys.stdout)

    def do_export(self, arg):
        "export [PATH] [FILE]  JSON dump of a subtree"
        def f():
            parts = shlex.split(arg)
            node = self._node(parts[0] if parts else "")
            do_export(self.doc, node, parts[1] if len(parts) > 1 else None, None, sys.stdout)
        self._run(f)

    def do_syncback(self, arg):
        "syncback OUT [PATH] [--force] [--collapse-models] [--scripts-only] [--no-extra] [--no-assets] [--no-terrain] [--src DIR]"
        def f():
            p = argparse.ArgumentParser(prog="syncback", add_help=False)
            p.add_argument("out"); p.add_argument("path", nargs="?", default="")
            p.add_argument("--src", default="src"); p.add_argument("--force", action="store_true")
            p.add_argument("--collapse-models", action="store_true")
            p.add_argument("--scripts-only", action="store_true")
            p.add_argument("--no-extra", action="store_true")
            p.add_argument("--no-assets", action="store_true")
            p.add_argument("--no-terrain", action="store_true")
            ns = p.parse_args(shlex.split(arg))
            do_syncback(self.doc, self._node(ns.path), ns.out, sys.stdout, ns.src,
                        ns.collapse_models, ns.scripts_only, ns.force, not ns.no_extra,
                        not ns.no_assets, not ns.no_terrain)
        try:
            self._run(f)
        except SystemExit:
            print("usage: " + self.do_syncback.__doc__)

    def do_sourcemap(self, arg):
        "sourcemap [PATH]      print the sourcemap.json syncback would write"
        self._run(lambda: do_sourcemap(self.doc, self._node(arg.strip()), False, False, sys.stdout))

    def do_quit(self, arg):
        "quit"
        return True

    do_exit = do_EOF = do_quit

    def emptyline(self):
        pass


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description="Browse Kinemium .kine files")
    ap.add_argument("file")
    sub = ap.add_subparsers(dest="command")
    sub.add_parser("info")
    p = sub.add_parser("tree"); p.add_argument("path", nargs="?", default=""); p.add_argument("-d", "--depth", type=int)
    p.add_argument("-i", "--index", action="store_true", help="show preorder indices")
    p = sub.add_parser("props"); p.add_argument("path", nargs="?", default=""); p.add_argument("-f", "--filter"); p.add_argument("--json", action="store_true")
    p = sub.add_parser("get"); p.add_argument("path"); p.add_argument("prop")
    p = sub.add_parser("find"); p.add_argument("--class", dest="cls"); p.add_argument("--name"); p.add_argument("--prop"); p.add_argument("--under", default=""); p.add_argument("--limit", type=int)
    sub.add_parser("assets")
    p = sub.add_parser("extract"); p.add_argument("id"); p.add_argument("out")
    p = sub.add_parser("terrain"); p.add_argument("--cells", type=int, default=0)
    p = sub.add_parser("export"); p.add_argument("path", nargs="?", default=""); p.add_argument("-o", "--output"); p.add_argument("-d", "--depth", type=int)
    p = sub.add_parser("syncback"); p.add_argument("out"); p.add_argument("path", nargs="?", default="")
    p.add_argument("--src", default="src", help="source directory name inside OUT")
    p.add_argument("--force", action="store_true", help="write into a non-empty directory")
    p.add_argument("--collapse-models", action="store_true", help="one .model.json per script-free subtree")
    p.add_argument("--scripts-only", action="store_true", help="sourcemap lists only scripts and their ancestors")
    p.add_argument("--no-extra", action="store_true"); p.add_argument("--no-assets", action="store_true")
    p.add_argument("--no-terrain", action="store_true")
    p = sub.add_parser("sourcemap"); p.add_argument("path", nargs="?", default="")
    p.add_argument("--collapse-models", action="store_true"); p.add_argument("--scripts-only", action="store_true")
    ns = ap.parse_args(argv)

    try:
        doc = KineFile.open(ns.file)
        out = sys.stdout
        c = ns.command
        if c is None:
            print(f"Loaded {ns.file} (v{doc.version}, {len(doc.all):,} instances). 'help' lists commands.")
            Shell(doc).cmdloop()
        elif c == "info": do_info(doc, out)
        elif c == "tree": do_tree(doc, doc.resolve(ns.path), ns.depth, out, ns.index)
        elif c == "props": do_props(doc, doc.resolve(ns.path), ns.filter, out, ns.json)
        elif c == "get": do_get(doc, doc.resolve(ns.path), ns.prop, out)
        elif c == "find": do_find(doc, doc.resolve(ns.under), ns.cls, ns.name, ns.prop, out, ns.limit)
        elif c == "assets": do_assets(doc, out)
        elif c == "extract": do_extract(doc, ns.id, ns.out, out)
        elif c == "terrain": do_terrain(doc, ns.cells, out)
        elif c == "export": do_export(doc, doc.resolve(ns.path), ns.output, ns.depth, out)
        elif c == "syncback":
            do_syncback(doc, doc.resolve(ns.path), ns.out, out, ns.src, ns.collapse_models,
                        ns.scripts_only, ns.force, not ns.no_extra, not ns.no_assets, not ns.no_terrain)
        elif c == "sourcemap": do_sourcemap(doc, doc.resolve(ns.path), ns.collapse_models, ns.scripts_only, out)
    except (KineError, OSError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    except BrokenPipeError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

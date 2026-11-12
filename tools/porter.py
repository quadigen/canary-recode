#!/usr/bin/env python3
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import math
import re
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import threading
import os
import random
import struct
import sys
import time
# ---------------------------------------------------------------------------
# KINE constants (mirror the Odin serializer)
# ---------------------------------------------------------------------------
KINE_MAGIC = b"KINE"

# Match the engine's assetstore.Asset_Kind ordering. Mesh=1 is also used by
# the existing CSG import path; verify these values if Asset_Kind ever changes.
ASSET_MESH, ASSET_TEXTURE, ASSET_AUDIO, ASSET_DATA = 1, 2, 3, 4
MAX_ASSET_BYTES = 32 * 1024 * 1024
MAX_ASSET_TOTAL_BYTES = 512 * 1024 * 1024
MAX_ASSET_COUNT = 8192
RBX_ASSET_ID = re.compile(r"^(?:rbxassetid://|https?://(?:www\.)?roblox\.com/asset/\?id=)([0-9]+)(?:[&#?].*)?$", re.I)
ASSET_PROPERTY_KINDS = {
    "MeshId": ASSET_MESH,
    "MeshContent": ASSET_MESH,
    "TextureId": ASSET_TEXTURE,
    "Texture": ASSET_TEXTURE,
    "Image": ASSET_TEXTURE,
    "SoundId": ASSET_AUDIO,
    "ColorMap": ASSET_TEXTURE,
    "AlbedoMap": ASSET_TEXTURE,
    "NormalMap": ASSET_TEXTURE,
    "RoughnessMap": ASSET_TEXTURE,
    "MetalnessMap": ASSET_TEXTURE,
    "HeightMap": ASSET_TEXTURE,
    "AOMap": ASSET_TEXTURE,
    "AmbientOcclusionMap": ASSET_TEXTURE,
    "EmissiveMap": ASSET_TEXTURE,
}

TAG_NIL, TAG_BOOL, TAG_NUMBER, TAG_INTEGER, TAG_STRING, TAG_VECTOR3, TAG_USERDATA, TAG_ENUM = range(8)
TAG_INSTANCE_REF = 19
DT_AXES, DT_BRICKCOLOR, DT_CFRAME, DT_COLOR3, DT_COLORSEQUENCE = 0, 1, 2, 3, 4
DT_FACES, DT_FONT, DT_NUMBERRANGE, DT_NUMBERSEQUENCE = 7, 8, 9, 10
DT_PHYSICALPROPERTIES = 12
DT_UDIM, DT_UDIM2, DT_VECTOR2, DT_VECTOR3INT16 = 18, 19, 21, 24
# ---------------------------------------------------------------------------
# Small encoders
# ---------------------------------------------------------------------------
def var_u32(v):
    out = bytearray()
    while v >= 0x80:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)
    return bytes(out)
def kstr(b):
    if isinstance(b, str):
        b = b.encode("utf-8")
    return var_u32(len(b)) + b
def enc_nil():
    return bytes([TAG_NIL])
def enc_bool(v):
    return bytes([TAG_BOOL, 1 if v else 0])
def enc_number(v):
    return bytes([TAG_NUMBER]) + struct.pack("<d", v)
def enc_integer(v):
    return bytes([TAG_INTEGER]) + struct.pack("<q", v)
def enc_string(b):
    return bytes([TAG_STRING]) + kstr(b)
def enc_vector3(x, y, z):
    return bytes([TAG_VECTOR3]) + struct.pack("<3f", x, y, z)
def enc_enum(name, value):
    return bytes([TAG_ENUM]) + kstr(name) + struct.pack("<q", value)
def enc_ud(dt_id, payload):
    return bytes([TAG_USERDATA]) + struct.pack("<H", dt_id) + payload
# ---------------------------------------------------------------------------
# LZ4 / zstd chunk decompression
# ---------------------------------------------------------------------------
def lz4_block_decompress(src, expected):
    out = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]
        i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]
                i += 1
                lit += b
                if b != 255:
                    break
        out += src[i:i + lit]
        i += lit
        if i >= n:
            break
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        mlen = token & 15
        if mlen == 15:
            while True:
                b = src[i]
                i += 1
                mlen += b
                if b != 255:
                    break
        mlen += 4
        start = len(out) - offset
        if offset <= 0 or start < 0:
            raise ValueError("bad LZ4 offset")
        if offset >= mlen:
            out += out[start:start + mlen]
        else:
            for j in range(mlen):
                out.append(out[start + j])
    if len(out) != expected:
        raise ValueError("LZ4 size mismatch (%d != %d)" % (len(out), expected))
    return bytes(out)
def decompress(data, expected):
    if data[:4] == b"\x28\xb5\x2f\xfd":
        try:
            import zstandard
        except ImportError:
            raise SystemExit("This file uses zstd chunks: pip install zstandard")
        return zstandard.ZstdDecompressor().decompress(data, max_output_size=expected)
    return lz4_block_decompress(data, expected)
# ---------------------------------------------------------------------------
# RBXM binary reader
# ---------------------------------------------------------------------------
class Buf:
    def __init__(self, data):
        self.d = data
        self.p = 0
    def take(self, n):
        if n < 0 or self.p + n > len(self.d):
            raise ValueError("unexpected end of chunk")
        r = self.d[self.p:self.p + n]
        self.p += n
        return r
    def u8(self):
        return self.take(1)[0]
    def u32(self):
        return struct.unpack("<I", self.take(4))[0]
    def string(self):
        return self.take(self.u32())
    def _columns(self, n, size):
        raw = self.take(n * size)
        cols = [raw[k * n:(k + 1) * n] for k in range(size)]
        return [int.from_bytes(bytes(t), "big") for t in zip(*cols)] if n else []
    def raw_u32s(self, n):
        return self._columns(n, 4)
    def ints(self, n):  # zigzag, 32-bit
        return [(v >> 1) ^ -(v & 1) for v in self._columns(n, 4)]
    def ints64(self, n):
        return [(v >> 1) ^ -(v & 1) for v in self._columns(n, 8)]
    def floats(self, n):
        out = []
        for v in self._columns(n, 4):
            bits = (v >> 1) | ((v & 1) << 31)
            out.append(struct.unpack("<f", struct.pack("<I", bits))[0])
        return out
    def refs(self, n):
        out, acc = [], 0
        for v in self.ints(n):
            acc += v
            out.append(acc)
        return out
    def le_floats(self, n):
        return list(struct.unpack("<%df" % n, self.take(4 * n)))
# Axis-aligned CFrame rotation ids -> row-major 3x3 (r00 r01 r02 r10 ... r22)
ROTATIONS = {
    0x02: (1, 0, 0, 0, 1, 0, 0, 0, 1), 0x03: (1, 0, 0, 0, 0, -1, 0, 1, 0),
    0x05: (1, 0, 0, 0, -1, 0, 0, 0, -1), 0x06: (1, 0, 0, 0, 0, 1, 0, -1, 0),
    0x07: (0, 1, 0, 1, 0, 0, 0, 0, -1), 0x09: (0, 0, 1, 1, 0, 0, 0, 1, 0),
    0x0A: (0, -1, 0, 1, 0, 0, 0, 0, 1), 0x0C: (0, 0, -1, 1, 0, 0, 0, -1, 0),
    0x0D: (0, 1, 0, 0, 0, 1, 1, 0, 0), 0x0E: (0, 0, -1, 0, 1, 0, 1, 0, 0),
    0x10: (0, -1, 0, 0, 0, -1, 1, 0, 0), 0x11: (0, 0, 1, 0, -1, 0, 1, 0, 0),
    0x14: (-1, 0, 0, 0, 1, 0, 0, 0, -1), 0x15: (-1, 0, 0, 0, 0, 1, 0, 1, 0),
    0x17: (-1, 0, 0, 0, -1, 0, 0, 0, 1), 0x18: (-1, 0, 0, 0, 0, -1, 0, -1, 0),
    0x19: (0, 1, 0, -1, 0, 0, 0, 0, 1), 0x1B: (0, 0, -1, -1, 0, 0, 0, 1, 0),
    0x1C: (0, -1, 0, -1, 0, 0, 0, 0, -1), 0x1E: (0, 0, 1, -1, 0, 0, 0, -1, 0),
    0x1F: (0, 1, 0, 0, 0, -1, -1, 0, 0), 0x20: (0, 0, 1, 0, 1, 0, -1, 0, 0),
    0x22: (0, -1, 0, 0, 0, 1, -1, 0, 0), 0x23: (0, 0, -1, 0, -1, 0, -1, 0, 0),
}
# Token (enum) properties: the RBXM only stores the integer.
DEFAULT_ENUMS = {
    "Shape": "PartType", "Material": "Material", "FormFactor": "FormFactor",
    "TopSurface": "SurfaceType", "BottomSurface": "SurfaceType",
    "LeftSurface": "SurfaceType", "RightSurface": "SurfaceType",
    "FrontSurface": "SurfaceType", "BackSurface": "SurfaceType",
    "Face": "NormalId", "TextXAlignment": "TextXAlignment",
    "TextYAlignment": "TextYAlignment", "SizeConstraint": "SizeConstraint",
    "SortOrder": "SortOrder", "FillDirection": "FillDirection",
    "HorizontalAlignment": "HorizontalAlignment",
    "VerticalAlignment": "VerticalAlignment", "ScaleType": "ScaleType",
    "ResamplerMode": "ResamplerMode", "CollisionFidelity": "CollisionFidelity",
    "RenderFidelity": "RenderFidelity", "ZIndexBehavior": "ZIndexBehavior",
    "AutomaticSize": "AutomaticSize", "BorderMode": "BorderMode",
    "ApplyStrokeMode": "ApplyStrokeMode", "LineJoinMode": "LineJoinMode",
    "CameraType": "CameraType", "Technology": "Technology", "RunContext": "RunContext",
    "TextTruncate": "TextTruncate", "RigType": "RigType",
    "DisplayDistanceType": "HumanoidDisplayDistanceType",
    "HealthDisplayType": "HumanoidHealthDisplayType", "NameOcclusion": "NameOcclusion",
    "RollOffMode": "RollOffMode", "HorizontalFlex": "UIFlexAlignment",
    "VerticalFlex": "UIFlexAlignment", "ItemLineAlignment": "ItemLineAlignment",
    "StartCorner": "StartCorner", "ScrollingDirection": "ScrollingDirection",
    "VerticalScrollBarPosition": "VerticalScrollBarPosition",
    "HorizontalScrollBarInset": "ScrollBarInset", "VerticalScrollBarInset": "ScrollBarInset",
    "ElasticBehavior": "ElasticBehavior", "AutomaticCanvasSize": "AutomaticSize",
    "SelectionBehaviorUp": "SelectionBehavior", "SelectionBehaviorDown": "SelectionBehavior",
    "SelectionBehaviorLeft": "SelectionBehavior", "SelectionBehaviorRight": "SelectionBehavior",
    "ResampleMode": "ResamplerMode", "FieldOfViewMode": "FieldOfViewMode",
    "ScreenInsets": "ScreenInsets", "SafeAreaCompatibility": "SafeAreaCompatibility",
    "TextInputType": "TextInputType", "Axis": "Axis",
    "EasingStyle": "EasingStyle", "EasingDirection": "EasingDirection",
    "HingeConstraint.ActuatorType": "ActuatorType",
    "Part.Font": "Font", "TextLabel.Font": "Font", "TextButton.Font": "Font",
    "TextBox.Font": "Font",
}
PROP_RENAMES = {"size": "Size", "Color3uint8": "Color"}
REFERENCE_PROPERTIES = {
    **{cls: {"Attachment0": "Attachment0", "Attachment1": "Attachment1"}
       for cls in ("HingeConstraint", "RopeConstraint", "SpringConstraint")},
    "WeldConstraint": {"Part0Internal": "Part0", "Part1Internal": "Part1",
                       "Part0": "Part0", "Part1": "Part1"},
}
PRIMITIVE_SHAPES = {"WedgePart": 3, "CornerWedgePart": 4, "TrussPart": 7}
# Roblox's own integer values, for enums whose Kinemium numbering may differ.
# Used with --enum-values to convert by item NAME instead of by number.
ROBLOX_ENUMS = {
    "Material": {
        "Plastic": 256, "SmoothPlastic": 272, "Neon": 288, "Wood": 512, "WoodPlanks": 528,
        "Marble": 784, "Basalt": 788, "Slate": 800, "CrackedLava": 804, "Concrete": 816,
        "Limestone": 820, "Granite": 832, "Pavement": 836, "Brick": 848, "Pebble": 864,
        "Cobblestone": 880, "Rock": 896, "Sandstone": 912, "CorrodedMetal": 1040,
        "DiamondPlate": 1056, "Foil": 1072, "Metal": 1088, "Grass": 1280, "LeafyGrass": 1284,
        "Sand": 1296, "Fabric": 1312, "Snow": 1328, "Mud": 1344, "Ground": 1360,
        "Asphalt": 1376, "Salt": 1392, "Ice": 1536, "Glacier": 1552, "Glass": 1568,
        "ForceField": 1584, "Air": 1792, "Water": 2048,
    },
}
ENUM_REMAP = {}  # enum name -> {roblox value: kinemium value}
def build_enum_remap(kine_values):
    """kine_values: {"Enum": {"Item": value}}; optional "_roblox" key adds Roblox tables."""
    kine_values = dict(kine_values)
    ROBLOX_ENUMS.update(kine_values.pop("_roblox", {}))
    for enum, kmap in kine_values.items():
        rmap = ROBLOX_ENUMS.get(enum)
        if rmap is None:
            print("warning: no Roblox value table for enum %s; add one under \"_roblox\"" % enum, file=sys.stderr)
            continue
        ENUM_REMAP[enum] = {rv: kmap[name] for name, rv in rmap.items() if name in kmap}
# --- Built-in conversion for enums whose Kinemium numbering differs from Roblox ---
ROBLOX_ENUMS.update({
    "VerticalAlignment": {"Center": 0, "Top": 1, "Bottom": 2},
    "ApplyStrokeMode": {"Contextual": 1, "Border": 2},
    "CameraType": {"Fixed": 0, "Watch": 1, "Attach": 2, "Track": 3, "Follow": 4,
                   "Custom": 5, "Scriptable": 6, "Orbital": 7},
    "RigType": {"R6": 0, "R15": 1},
})
KINE_ENUMS = {  # taken from the engine's enum definitions
    "Material": {"SmoothPlastic": 0, "Wood": 1, "Brick": 2, "Grass": 3, "Concrete": 4,
                 "Slate": 5, "Glass": 6, "Neon": 7, "Sand": 8, "Water": 9, "debug": 10, "Air": 11},
    "VerticalAlignment": {"Top": 0, "Center": 1, "Bottom": 2},
    "ApplyStrokeMode": {"Contextual": 0, "Border": 1},
    "CameraType": {"Custom": 0, "Scriptable": 1, "Orbital": 2, "FirstPerson": 3,
                   "ThirdPerson": 4, "Follow": 5, "Shoulder": 8, "TopDown": 9, "Isometric": 10},
    "RigType": {"R15": 0},
}
# Roblox item name -> Kinemium item name, where the names differ. Items with no
# counterpart (e.g. CameraType.Fixed, RigType.R6) are skipped.
ENUM_ITEM_ALIASES = {
    "Material": {
        "Plastic": "SmoothPlastic", "WoodPlanks": "Wood", "Marble": "Slate", "Basalt": "Slate",
        "CrackedLava": "Slate", "Limestone": "Concrete", "Granite": "Slate", "Pavement": "Concrete",
        "Pebble": "Concrete", "Cobblestone": "Brick", "Rock": "Slate", "Sandstone": "Sand",
        "CorrodedMetal": "SmoothPlastic", "DiamondPlate": "SmoothPlastic", "Foil": "SmoothPlastic",
        "Metal": "SmoothPlastic", "LeafyGrass": "Grass", "Fabric": "SmoothPlastic",
        "Snow": "SmoothPlastic", "Mud": "Sand", "Ground": "Grass", "Asphalt": "Concrete",
        "Salt": "Sand", "Ice": "Glass", "Glacier": "Glass", "ForceField": "Neon",
    },
}
def init_default_remaps():
    for enum, kmap in KINE_ENUMS.items():
        aliases = ENUM_ITEM_ALIASES.get(enum, {})
        remap = {}
        for rname, rvalue in ROBLOX_ENUMS[enum].items():
            kname = aliases.get(rname, rname)
            if kname in kmap:
                remap[rvalue] = kmap[kname]
        ENUM_REMAP[enum] = remap
init_default_remaps()
# Classes registered by Register_Default_Classes in the Kinemium engine.
# Services (Workspace, Lighting, ...) and anything registered elsewhere are NOT
# here; extend with --allow-class / --classes-file or disable with --no-class-filter.
DEFAULT_CLASSES = """
Instance ArcHandles Atmosphere BasePart BlurEffect BlurImageFilter BloomEffect
BindableEvent BindableFunction BoolValue BrickColorValue Camera CFrameValue CharacterAnimator CharacterController
CharacterInput CharacterModel CharacterMotor CollisionController Color3Value
ColorCorrectionEffect ColorSequenceValue Configuration Decal DepthOfFieldEffect DoubleConstrainedValue
EditableMesh Folder Frame GroundDetector GuiButton GuiObject Handles Highlight Humanoid
ImageButton ImageLabel InputObject IntConstrainedValue IntValue Light LocalScript
MeshPart Model ModuleScript MovementController NumberRangeValue NumberSequenceValue
UnionOperation NegateOperation IntersectOperation HingeConstraint WeldConstraint RopeConstraint SpringConstraint
NumberValue ObjectValue Part PointLight PostProcessShader RayValue RemoteEvent
RemoteFunction RotationController SSAOEffect ScreenGui Script ScrollingFrame Sound
SpotLight StarterCharacterScripts StateMachine StringValue SunRaysEffect
SurfaceGui SurfaceLight SyntaxHighlighter TextBox TextButton TextLabel Tween UIBackdrop UICorner
UIGradient UIGridLayout UIListLayout UIShadow UIStroke ValueBase Vector2Value
Vector3Value PlayerScripts Attachment Terrain UISizeConstraint UIPadding
""".split()
MAP_CONTENT_SERVICES = set("""
Workspace ReplicatedFirst ReplicatedStorage Lighting SoundService StarterGui
StarterPack StarterPlayer ServerScriptService ServerStorage
""".split())
def subtree_size(inst):
    total = 1
    for child in inst.children:
        total += subtree_size(child)
    return total
def dprint(opts, message):
    if opts.debug:
        print(message)
def record_drop(opts, inst, reason):
    stats = opts.stats["dropped_classes"]
    stats[inst.cls] = stats.get(inst.cls, 0) + 1
    opts.stats["dropped_instances"] += subtree_size(inst)
    dprint(opts, "drop  %s %r subtree=%d reason=%s" % (inst.cls, inst.name, subtree_size(inst), reason))
class Inst:
    __slots__ = ("cls", "ref", "name", "archivable", "props", "attrs", "children", "parent", "is_service")
    def __init__(self, cls, ref, is_service=False):
        self.cls = cls
        self.ref = ref
        self.name = cls
        self.archivable = True
        self.props = {}  # key(str) -> encoded bytes or an instance referent
        self.attrs = []  # [(name bytes, encoded value bytes)]
        self.children = []
        self.parent = None
        self.is_service = is_service
class Options:
    def __init__(self):
        self.enum_map = dict(DEFAULT_ENUMS)
        self.allowed_classes = set(DEFAULT_CLASSES) | set(MAP_CONTENT_SERVICES)
        self.aliases = {
            "SpawnLocation": "Part", "Seat": "Part", "VehicleSeat": "Part", "TrussPart": "Part",
            "StarterPlayerScripts": "PlayerScripts",
            "WedgePart": "Part", "CornerWedgePart": "Part",
        }
        self.drop_classes = set()
        self.drop_props = {"SourceAssetId"}
        self.kine_version = 8
        self.mesh_assets = {}
        self.embedded_assets = {}
        self.resolved_assets = {}
        self.embedded_asset_bytes = 0
        self.asset_workers = 4
        self.asset_verbose = False
        self.download_assets = True
        self.downloader = None
        self.root_class = "Model"
        self.debug = False
        self.stats = {
            "unsupported_types": {},
            "unmapped_enums": set(),
            "dropped_classes": {},
            "dropped_instances": 0,
            "kept_instances": 0,
            "services": [],
            "dropped_attributes": 0,
            "imported_unions": 0,
            "downloaded_assets": 0,
            "asset_failures": 0,
        }
# ---------------------------------------------------------------------------
# Property decoders: each returns a list (len n) of (tag, value) or None
# ---------------------------------------------------------------------------
ATTRIBUTE_NAME_MAX = 100
ATTRIBUTE_NAME_CHARS = set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-. /"
)
def attribute_name_is_valid(name):
    raw = name.decode("utf-8", "replace") if isinstance(name, bytes) else name
    if not raw or len(raw) > ATTRIBUTE_NAME_MAX:
        return False
    if raw.startswith("RBX"):
        return False
    return all(c in ATTRIBUTE_NAME_CHARS for c in raw)
def parse_attributes(raw):
    out = []
    try:
        b = Buf(raw)
        count = b.u32()
        for _ in range(count):
            name = b.string()
            t = b.u8()
            if t == 0x02:
                out.append((name, enc_string(b.string())))
            elif t == 0x03:
                out.append((name, enc_bool(b.u8() != 0)))
            elif t == 0x05:
                out.append((name, enc_number(struct.unpack("<f", b.take(4))[0])))
            elif t == 0x06:
                out.append((name, enc_number(struct.unpack("<d", b.take(8))[0])))
            else:
                break  # unknown attribute type: keep what was parsed so far
    except (ValueError, struct.error):
        pass
    return out
def decode_prop(t, b, n, enum_name):
    E = lambda x: ("e", x)
    if t == 0x01:
        return [("s", b.string()) for _ in range(n)]
    if t == 0x02:
        return [("b", b.u8() != 0) for _ in range(n)]
    if t == 0x03:
        return [E(enc_number(float(v))) for v in b.ints(n)]
    if t == 0x04:
        return [E(enc_number(v)) for v in b.floats(n)]
    if t == 0x05:
        return [E(enc_number(struct.unpack("<d", b.take(8))[0])) for _ in range(n)]
    if t == 0x06:  # UDim
        sc, off = b.floats(n), b.ints(n)
        return [E(enc_ud(DT_UDIM, struct.pack("<ff", sc[i], float(off[i])))) for i in range(n)]
    if t == 0x07:  # UDim2
        sx, sy, ox, oy = b.floats(n), b.floats(n), b.ints(n), b.ints(n)
        return [E(enc_ud(DT_UDIM2, struct.pack("<ffff", sx[i], float(ox[i]), sy[i], float(oy[i])))) for i in range(n)]
    if t == 0x09:  # Faces (Right=1 Top=2 Back=4 Left=8 Bottom=16 Front=32)
        out = []
        for _ in range(n):
            m = b.u8()
            top, bottom, left, right, front, back = (m >> 1) & 1, (m >> 4) & 1, (m >> 3) & 1, m & 1, (m >> 5) & 1, (m >> 2) & 1
            out.append(E(enc_ud(DT_FACES, bytes([top, bottom, left, right, front, back]))))
        return out
    if t == 0x0A:  # Axes (X=1 Y=2 Z=4)
        out = []
        for _ in range(n):
            m = b.u8()
            out.append(E(enc_ud(DT_AXES, bytes([m & 1, (m >> 1) & 1, (m >> 2) & 1]))))
        return out
    if t == 0x0B:  # BrickColor
        return [E(enc_ud(DT_BRICKCOLOR, struct.pack("<i", v))) for v in b.raw_u32s(n)]
    if t == 0x0C:  # Color3
        r, g, bl = b.floats(n), b.floats(n), b.floats(n)
        return [E(enc_ud(DT_COLOR3, struct.pack("<fff", r[i], g[i], bl[i]))) for i in range(n)]
    if t == 0x0D:  # Vector2
        x, y = b.floats(n), b.floats(n)
        return [E(enc_ud(DT_VECTOR2, struct.pack("<ff", x[i], y[i]))) for i in range(n)]
    if t == 0x0E:  # Vector3
        x, y, z = b.floats(n), b.floats(n), b.floats(n)
        return [E(enc_vector3(x[i], y[i], z[i])) for i in range(n)]
    if t == 0x10:  # CFrame
        rots = []
        for _ in range(n):
            rid = b.u8()
            if rid == 0:
                rots.append(b.le_floats(9))
            elif rid in ROTATIONS:
                rots.append(ROTATIONS[rid])
            else:
                raise ValueError("unknown CFrame rotation id %#x" % rid)
        x, y, z = b.floats(n), b.floats(n), b.floats(n)
        return [E(enc_ud(DT_CFRAME, struct.pack("<12f", x[i], y[i], z[i], *rots[i]))) for i in range(n)]
    if t == 0x12:  # Token / enum
        vals = b.raw_u32s(n)
        if enum_name is None:
            return None
        remap = ENUM_REMAP.get(enum_name)
        if remap is not None:  # convert by item name; unknown items are skipped
            return [E(enc_enum(enum_name, remap[v])) if v in remap else None for v in vals]
        return [E(enc_enum(enum_name, v)) for v in vals]
    if t == 0x14:  # Vector3int16
        return [E(enc_ud(DT_VECTOR3INT16, b.take(6))) for _ in range(n)]
    if t == 0x15:  # NumberSequence
        out = []
        for _ in range(n):
            cnt = b.u32()
            pts = [struct.unpack("<3f", b.take(12)) for _ in range(cnt)]
            out.append(E(enc_ud(DT_NUMBERSEQUENCE, struct.pack("<I", cnt) + b"".join(struct.pack("<3f", *p) for p in pts))))
        return out
    if t == 0x16:  # ColorSequence (keypoints carry an unused envelope float)
        out = []
        for _ in range(n):
            cnt = b.u32()
            body = b""
            for _ in range(cnt):
                tm, r, g, bl, _env = struct.unpack("<5f", b.take(20))
                body += struct.pack("<4f", tm, r, g, bl)
            out.append(E(enc_ud(DT_COLORSEQUENCE, struct.pack("<I", cnt) + body)))
        return out
    if t == 0x17:  # NumberRange
        return [E(enc_ud(DT_NUMBERRANGE, b.take(8))) for _ in range(n)]
    if t == 0x19:  # PhysicalProperties: bit 0 custom, bit 1 acoustic absorption
        out = []
        for _ in range(n):
            flags = b.u8()
            if flags & 1:
                # Kinemium stores five floats; Roblox can append an optional
                # sixth (AcousticAbsorption), which we must consume but omit.
                body = b.take(20)
                if flags & 2:
                    b.take(4)
                out.append(E(enc_ud(DT_PHYSICALPROPERTIES, body)))
            else:
                # No custom values. The acoustic flag alone does not imply
                # that a standalone floating-point payload is present.
                out.append(None)
        return out
    if t == 0x1A:  # Color3uint8
        r, g, bl = b.take(n), b.take(n), b.take(n)
        return [E(enc_ud(DT_COLOR3, struct.pack("<fff", r[i] / 255.0, g[i] / 255.0, bl[i] / 255.0))) for i in range(n)]
    if t == 0x1B:  # Int64
        return [E(enc_number(float(v))) for v in b.ints64(n)]  # never emit the Integer tag: Luau has no integer type
    if t == 0x20:  # Font
        out = []
        for _ in range(n):
            family = b.string()
            weight = struct.unpack("<H", b.take(2))[0]
            style = b.u8()
            b.string()  # cached face id
            out.append(E(enc_ud(DT_FONT, kstr(family) + struct.pack("<qq", weight, style))))
        return out
    return None  # Ref, Rect, Ray, SharedString, OptionalCFrame, UniqueId, ...
# ---------------------------------------------------------------------------
# Roblox asset delivery and KINE asset-table embedding
# ---------------------------------------------------------------------------

def content_id(data):
    # FNV-1a 64-bit + length, identical to the existing CSG asset IDs.
    value = 14695981039346656037
    for byte in data:
        value = ((value ^ byte) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return f"{((value ^ len(data)) * 1099511628211) & 0xFFFFFFFFFFFFFFFF:016x}"


def encoded_string_bytes(value):
    if not isinstance(value, bytes) or not value or value[0] != TAG_STRING:
        return None
    number, shift, index = 0, 0, 1
    for _ in range(5):
        if index >= len(value):
            return None
        b = value[index]
        index += 1
        number |= (b & 0x7f) << shift
        if not b & 0x80:
            return value[index:] if index + number == len(value) else None
        shift += 7
    return None


def asset_extension(data, kind):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if data.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return ".webp"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return ".gif"
    if data.startswith(b"OggS"):
        return ".ogg"
    if data.startswith(b"RIFF") and data[8:12] == b"WAVE":
        return ".wav"
    if data.startswith(b"fLaC"):
        return ".flac"
    if data.startswith(b"ID3") or (len(data) > 2 and data[0] == 0xff and data[1] & 0xe0 == 0xe0):
        return ".mp3"
    if data.startswith(b"glTF"):
        return ".glb"
    if data.lstrip().startswith((b"v ", b"# OBJ")):
        return ".obj"
    if data.startswith(b"version "):
        return ".mesh"
    return None


def filemesh_to_obj(data):
    """Convert FileMesh 1-5's static LOD0 geometry to OBJ.

    Bone/skin deformation is intentionally not exported; v6+ chunked and
    Draco-encoded formats require a separate decoder.
    """
    header, separator, remainder = data.partition(b"\n")
    if not separator or not header.startswith(b"version "):
        raise ValueError("not a Roblox FileMesh")
    version = header[8:].decode("ascii", "replace")
    if version in ("1.00", "1.01"):
        countline, separator, body = remainder.partition(b"\n")
        if not separator:
            raise ValueError("missing FileMesh face count")
        face_count = int(countline.strip())
        if face_count < 0 or face_count > 1_000_000:
            raise ValueError("invalid FileMesh face count")
        triplets = re.findall(rb"\[([^]\r\n]+)\]", body)
        if len(triplets) != face_count * 9:
            raise ValueError("invalid FileMesh v1 vertex data")
        vertices, normals, uvs = [], [], []
        for n in range(0, len(triplets), 3):
            pos = tuple(float(x.strip()) for x in triplets[n].split(b","))
            norm = tuple(float(x.strip()) for x in triplets[n + 1].split(b","))
            uv = tuple(float(x.strip()) for x in triplets[n + 2].split(b","))
            if len(pos) != 3 or len(norm) != 3 or len(uv) != 3:
                raise ValueError("invalid FileMesh v1 vertex")
            vertices.append(tuple(v * 0.5 if version == "1.00" else v for v in pos))
            normals.append(norm)
            uvs.append((uv[0], 1.0 - uv[1]))
        faces = [(i, i + 1, i + 2) for i in range(0, len(vertices), 3)]
    elif version in ("6.00", "7.00"):
        chunks = {}
        offset = 0
        while offset < len(remainder):
            if offset + 16 > len(remainder):
                raise ValueError("truncated FileMesh chunk header")
            name = remainder[offset:offset + 8].rstrip(b"\x00")
            chunk_version, size = struct.unpack_from("<II", remainder, offset + 8)
            offset += 16
            if size > len(remainder) - offset:
                raise ValueError("truncated FileMesh chunk")
            chunks[name] = (chunk_version, remainder[offset:offset + size])
            offset += size
        if b"COREMESH" not in chunks:
            raise ValueError("FileMesh has no COREMESH chunk")
        core_version, core = chunks[b"COREMESH"]
        if core_version == 1:
            if len(core) < 8:
                raise ValueError("truncated COREMESH")
            vertex_count = struct.unpack_from("<I", core)[0]
            if not 0 < vertex_count <= 3_000_000:
                raise ValueError("invalid COREMESH vertex count")
            offset = 4
            if offset + vertex_count * 40 + 4 > len(core):
                raise ValueError("truncated COREMESH vertices")
            vertices, normals, uvs = [], [], []
            for i in range(vertex_count):
                numbers = struct.unpack_from("<8f", core, offset + i * 40)
                vertices.append(numbers[:3])
                normals.append(numbers[3:6])
                uvs.append(numbers[6:8])
            offset += vertex_count * 40
            face_count = struct.unpack_from("<I", core, offset)[0]
            offset += 4
            if not 0 < face_count <= 3_000_000 or offset + face_count * 12 > len(core):
                raise ValueError("invalid COREMESH face count")
            faces = list(struct.iter_unpack("<III", core[offset:offset + face_count * 12]))
        elif core_version == 2:
            if len(core) < 4:
                raise ValueError("truncated Draco COREMESH")
            stream_size = struct.unpack_from("<I", core)[0]
            if stream_size <= 0 or 4 + stream_size > len(core):
                raise ValueError("invalid FileMesh Draco stream")
            try:
                import DracoPy
            except ImportError:
                raise ValueError("FileMesh v7 requires optional 'pip install DracoPy'") from None
            try:
                decoded = DracoPy.decode(core[4:4 + stream_size])
                vertices = [tuple(float(x) for x in row) for row in decoded.points]
                faces = [tuple(int(x) for x in row) for row in decoded.faces]
                draco_normals = getattr(decoded, "normals", None)
                draco_uvs = getattr(decoded, "tex_coord", None)
                normals = [tuple(float(x) for x in row) for row in draco_normals] if draco_normals is not None else []
                uvs = [tuple(float(x) for x in row) for row in draco_uvs] if draco_uvs is not None else []
            except Exception as exc:
                raise ValueError(f"could not decode Draco FileMesh: {exc}") from exc
        else:
            raise ValueError("unsupported COREMESH chunk version")
        if b"LODS" in chunks:
            lod_version, lod_data = chunks[b"LODS"]
            if lod_version == 1 and len(lod_data) >= 7:
                count = struct.unpack_from("<I", lod_data, 3)[0]
                if 2 <= count <= (len(lod_data) - 7) // 4:
                    lods = struct.unpack_from("<" + "I" * count, lod_data, 7)
                    if 0 <= lods[0] < lods[1] <= len(faces):
                        faces = faces[lods[0]:lods[1]]
    else:
        if version not in ("2.00", "3.00", "3.01", "4.00", "4.01", "5.00", "5.01"):
            raise ValueError("unsupported Roblox FileMesh " + version + " (requires a v6/v7 decoder)")
        if len(remainder) < 24:
            raise ValueError("truncated FileMesh header")
        if version.startswith("2."):
            header_size, vertex_stride, face_stride, vertex_count, face_count = struct.unpack_from("<HBBII", remainder)
            offset = header_size
            lod_count = 0
            bones = 0
        elif version.startswith("3."):
            header_size, vertex_stride, face_stride, lod_stride, lod_count, vertex_count, face_count = struct.unpack_from("<HBBHHII", remainder)
            if lod_stride != 4:
                raise ValueError("unsupported FileMesh LOD format")
            offset = header_size
            bones = 0
        else:
            header_size, _, vertex_count, face_count, lod_count, bones, _, _, _, _ = struct.unpack_from("<HHIIHHIHBB", remainder)
            if header_size not in (24, 32):
                raise ValueError("unsupported FileMesh header size")
            vertex_stride, face_stride = 40, 12
            offset = header_size
        if not 0 < vertex_count <= 3_000_000 or not 0 < face_count <= 3_000_000:
            raise ValueError("invalid FileMesh geometry counts")
        if vertex_stride not in (36, 40) or face_stride != 12:
            raise ValueError("unsupported FileMesh record stride")
        if offset + vertex_count * vertex_stride > len(remainder):
            raise ValueError("truncated FileMesh vertices")
        vertices, normals, uvs = [], [], []
        for i in range(vertex_count):
            numbers = struct.unpack_from("<8f", remainder, offset + i * vertex_stride)
            vertices.append(numbers[:3])
            normals.append(numbers[3:6])
            uvs.append(numbers[6:8])
        offset += vertex_count * vertex_stride
        if bones:
            offset += vertex_count * 8
        if offset + face_count * 12 + lod_count * 4 > len(remainder):
            raise ValueError("truncated FileMesh triangles/LODs")
        faces = list(struct.iter_unpack("<3I", remainder[offset:offset + face_count * 12]))
        offset += face_count * 12
        if lod_count >= 2:
            lods = struct.unpack_from("<" + "I" * lod_count, remainder, offset)
            if not 0 <= lods[0] < lods[1] <= len(faces):
                raise ValueError("invalid FileMesh LOD0 range")
            faces = faces[lods[0]:lods[1]]
    if not vertices or not faces or max(max(f) for f in faces) >= len(vertices):
        raise ValueError("invalid FileMesh indices")
    if any(not math.isfinite(v) for row in vertices for v in row):
        raise ValueError("non-finite FileMesh vertex")
    if not all(math.isfinite(v) for row in uvs for v in row):
        uvs = []
    if not all(math.isfinite(v) for row in normals for v in row):
        normals = []
    # Roblox positions use the mesh's original dimensions. Convert to the
    # [-1,+1] geometry domain used by the porter's CSG OBJ meshes.
    axes = list(zip(*vertices))
    mins, maxes = [min(a) for a in axes], [max(a) for a in axes]
    center = [(lo + hi) / 2 for lo, hi in zip(mins, maxes)]
    halves = [(hi - lo) / 2 for lo, hi in zip(mins, maxes)]
    lines = []
    for xyz in vertices:
        lines.append("v " + " ".join(f"{(v - c) / h if h else 0:.9g}" for v, c, h in zip(xyz, center, halves)) + "\n")
    if uvs:
        lines.extend(f"vt {uv[0]:.9g} {uv[1]:.9g}\n" for uv in uvs)
    if normals:
        for normal in normals:
            scaled = [v * h for v, h in zip(normal, halves)]
            magnitude = math.hypot(*scaled)
            if not magnitude:
                scaled, magnitude = list(normal), math.hypot(*normal)
            lines.append("vn " + " ".join(f"{v / magnitude if magnitude else 0:.9g}" for v in scaled) + "\n")
    for f in faces:
        corners = []
        for i in f:
            n = i + 1
            corners.append(f"{n}/{n}/{n}" if uvs and normals else f"{n}/{n}" if uvs else f"{n}//{n}" if normals else str(n))
        lines.append("f " + " ".join(corners) + "\n")
    return "".join(lines).encode("ascii")


class RestrictedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not RobloxDownloader.allowed_host(newurl):
            raise ValueError("asset delivery returned a URL outside Roblox's CDN")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected:
            # Do not forward account credentials from an API to a CDN.
            for key in list(redirected.headers):
                if key.lower() in ("cookie", "x-api-key", "authorization"):
                    del redirected.headers[key]
        return redirected


class RobloxDownloader:
    def __init__(self, api_key="", cookie="", timeout=8.0, retries=1, cache_dir=None):
        self.api_key = api_key
        self.cookie = cookie
        self.timeout = timeout
        self.retries = retries
        self.cache_dir = cache_dir
        self.opener = urllib.request.build_opener(RestrictedRedirect())
        self.cache = {}

    @staticmethod
    def allowed_host(url):
        u = urllib.parse.urlsplit(url)
        host = (u.hostname or "").lower()
        return u.scheme == "https" and (
            host in ("assetdelivery.roblox.com", "apis.roblox.com", "rbxcdn.com")
            or host.endswith(".rbxcdn.com")
            or host.endswith(".roblox.com")
        )

    def get(self, url, *, authenticated=False):
        if not self.allowed_host(url):
            raise ValueError("asset delivery returned an untrusted host")
        headers = {"User-Agent": "Kinemium-RBXM-Importer/1.1", "Accept": "*/*"}
        hostname = urllib.parse.urlsplit(url).hostname
        if authenticated and hostname == "apis.roblox.com" and self.api_key:
            headers["x-api-key"] = self.api_key
        elif authenticated and hostname == "assetdelivery.roblox.com" and self.cookie:
            headers["Cookie"] = ".ROBLOSECURITY=" + self.cookie
        request = urllib.request.Request(url, headers=headers)
        for attempt in range(self.retries + 1):
            try:
                with self.opener.open(request, timeout=self.timeout) as response:
                    content_len = response.headers.get("Content-Length")
                    if content_len and int(content_len) > MAX_ASSET_BYTES:
                        raise ValueError("asset exceeds the 32 MiB size limit")
                    # Read a bounded amount so a server cannot return arbitrarily
                    # large content. The socket timeout also applies while reading.
                    data = response.read(MAX_ASSET_BYTES + 1)
                    if len(data) > MAX_ASSET_BYTES:
                        raise ValueError("asset exceeds the 32 MiB size limit")
                    return data
            except urllib.error.HTTPError as exc:
                if exc.code not in (429, 500, 502, 503, 504) or attempt >= self.retries:
                    raise ValueError(f"HTTP {exc.code} from Roblox delivery") from exc
                time.sleep(min(1 + attempt, 3))
            except (TimeoutError, OSError) as exc:
                if attempt >= self.retries:
                    raise ValueError(f"network request failed: {exc}") from exc
        raise ValueError("Roblox download retry limit reached")

    def fetch(self, asset_id):
        # All IDs are validated before invoking this method. Repeated requests
        # for the same ID share the result, including cached failures.
        if asset_id in self.cache:
            result = self.cache[asset_id]
            if isinstance(result, Exception):
                raise result
            return result
        disk_path = None
        if self.cache_dir:
            disk_path = os.path.join(self.cache_dir, asset_id + ".bin")
            try:
                with open(disk_path, "rb") as file:
                    cached = file.read(MAX_ASSET_BYTES + 1)
                if cached and len(cached) <= MAX_ASSET_BYTES:
                    self.cache[asset_id] = cached
                    return cached
            except FileNotFoundError:
                pass
        try:
            if self.api_key:
                url = f"https://apis.roblox.com/asset-delivery-api/v1/assetId/{asset_id}"
            else:
                url = f"https://assetdelivery.roblox.com/v2/assetId/{asset_id}"
            data = self.get(url, authenticated=True)
            # AssetDelivery v2 returns JSON containing CDN locations, whereas
            # some API/legacy variants return the binary content directly.
            for _ in range(3):
                if not data.lstrip().startswith(b"{"):
                    break
                try:
                    metadata = json.loads(data)
                except (ValueError, UnicodeDecodeError):
                    break
                if not isinstance(metadata, dict):
                    break
                locations = metadata.get("locations") or []
                location = next((entry.get("location") for entry in locations
                                 if isinstance(entry, dict) and entry.get("location")), None)
                location = location or metadata.get("location")
                if not location:
                    details = metadata.get("errors", metadata.get("message", "no CDN location"))
                    raise ValueError("asset delivery response: " + str(details)[:140])
                data = self.get(location)
            if data.lstrip().startswith((b"{", b"[")):
                raise ValueError("asset endpoint returned JSON instead of asset bytes")
            if not data:
                raise ValueError("asset endpoint returned an empty file")
            if data.lstrip()[:16].lower().startswith((b"<!doctype html", b"<html")):
                raise ValueError("asset endpoint returned HTML, possibly an access/login error")
            self.cache[asset_id] = data
            if disk_path:
                try:
                    os.makedirs(self.cache_dir, exist_ok=True, mode=0o700)
                    tmp_path = disk_path + ".tmp-" + str(threading.get_ident())
                    with open(tmp_path, "wb") as file:
                        file.write(data)
                    os.replace(tmp_path, disk_path)
                except OSError:
                    pass  # Disk caching must never prevent asset import.
            return data
        except (OSError, ValueError, urllib.error.HTTPError) as exc:
            self.cache[asset_id] = exc
            raise


def extract_container_asset_target(data, kind):
    """Resolve a Roblox Decal/MeshPart wrapper to its actual payload ID.

    Roblox asset IDs may designate a model/XML container instead of the actual
    texture or FileMesh. Follow only explicit Content properties, never URLs in
    scripts or arbitrary text, and never arbitrary website URLs.
    """
    properties = (("Texture", "Image", "TextureId", "ColorMap")
                  if kind == ASSET_TEXTURE else
                  ("MeshId", "MeshContent") if kind == ASSET_MESH else ())
    if not properties or len(data) > 8 * 1024 * 1024:
        return None
    candidates = []
    if data.lstrip().startswith(b"<"):
        try:
            root = ET.fromstring(data)
        except ET.ParseError:
            return None
        for item in root.iter():
            name = item.attrib.get("name")
            if name not in properties:
                continue
            for node in item.iter():
                tag = node.tag.rsplit("}", 1)[-1].lower()
                if tag in ("url", "string", "content") and node.text:
                    candidates.append(node.text.strip())
    elif data.startswith(b"<roblox!"):
        # The asset itself may be a binary RBXM containing a MeshPart or Decal.
        # The ordinary parser already knows how to decode Content values.
        try:
            embedded = parse_rbxm(data, Options())
        except (ValueError, IndexError, struct.error):
            return None
        stack = list(embedded)
        while stack:
            inst = stack.pop()
            stack.extend(inst.children)
            for key in properties:
                raw = encoded_string_bytes(inst.props.get(key))
                if raw is not None:
                    candidates.append(raw.decode("utf-8", "replace"))
    for candidate in candidates:
        match = RBX_ASSET_ID.fullmatch(candidate)
        if match:
            return match.group(1)
    return None


def describe_payload(data):
    if data.lstrip().startswith(b"<"):
        return "Roblox XML/model wrapper without a usable content ID"
    if data.startswith(b"<roblox!"):
        return "Roblox binary model without a usable content ID"
    if data.lstrip().startswith((b"<!DOCTYPE html", b"<html")):
        return "HTML response (possibly an access or login error)"
    return "unrecognized binary signature " + data[:12].hex(" ")


def resolve_asset(downloader, asset_id, kind):
    seen = set()
    current_id = asset_id
    for depth in range(4):
        if current_id in seen:
            raise ValueError("asset container references form a cycle")
        seen.add(current_id)
        data = downloader.fetch(current_id)
        if len(data) > MAX_ASSET_BYTES:
            raise ValueError("asset exceeds the KINE per-asset size limit")
        ext = asset_extension(data, kind)
        accepted = {
            ASSET_TEXTURE: (".png", ".jpg", ".webp", ".gif"),
            ASSET_MESH: (".obj", ".glb", ".mesh"),
            ASSET_AUDIO: (".ogg", ".wav", ".mp3", ".flac"),
        }.get(kind)
        if accepted is None:
            if ext:
                return data, ext
        elif ext in accepted:
            if kind == ASSET_MESH and ext == ".mesh":
                converted = filemesh_to_obj(data)
                if len(converted) > MAX_ASSET_BYTES:
                    raise ValueError("converted OBJ exceeds the KINE per-asset size limit")
                return converted, ".obj"
            return data, ext
        target = extract_container_asset_target(data, kind)
        if target and target != current_id:
            current_id = target
            continue
        label = {ASSET_TEXTURE: "image", ASSET_MESH: "mesh", ASSET_AUDIO: "audio"}.get(kind, "asset")
        raise ValueError(f"not a supported {label}: {describe_payload(data)}")
    raise ValueError("nested asset references exceed four levels")


def iter_retained_instances(root, opts):
    stack = [root]
    while stack:
        inst = stack.pop()
        if inst.cls in opts.drop_classes:
            continue
        if opts.kine_version < 8 and inst.cls in REFERENCE_PROPERTIES:
            continue
        if opts.allowed_classes is not None and inst.cls not in opts.allowed_classes:
            continue
        yield inst
        stack.extend(reversed(inst.children))


def iter_asset_properties(inst, opts):
    for key, value in inst.props.items():
        if key not in ASSET_PROPERTY_KINDS:
            continue
        if key in opts.drop_props or (inst.cls + "." + key) in opts.drop_props:
            continue
        raw = encoded_string_bytes(value)
        if raw is None:
            continue
        match = RBX_ASSET_ID.fullmatch(raw.decode("utf-8", "replace").strip())
        if match:
            yield key, value, match.group(1), ASSET_PROPERTY_KINDS[key]


def prefetch_assets(root, opts):
    if not opts.download_assets or opts.kine_version < 3:
        return
    refs = {}
    for inst in iter_retained_instances(root, opts):
        for key, value, asset_id, kind in iter_asset_properties(inst, opts):
            refs.setdefault((asset_id, kind), (inst.cls, key))
    if not refs:
        return
    print(f"Fetching {len(refs)} unique Roblox assets ({opts.asset_workers} workers)...", flush=True)
    failures = []
    with ThreadPoolExecutor(max_workers=opts.asset_workers) as pool:
        futures = {pool.submit(resolve_asset, opts.downloader, asset_id, kind): (asset_id, kind)
                   for asset_id, kind in refs}
        report_interval = max(1, len(futures) // 10)
        for done, future in enumerate(as_completed(futures), 1):
            asset_id, kind = futures[future]
            try:
                opts.resolved_assets[(asset_id, kind)] = future.result()
            except (ValueError, OSError, struct.error, IndexError) as exc:
                opts.resolved_assets[(asset_id, kind)] = exc
                failures.append((asset_id, kind, str(exc)))
            if done == len(futures) or done % report_interval == 0:
                print(f"  Assets: {done}/{len(futures)} processed", flush=True)
    for asset_id, kind, error in failures[:12]:
        cls, prop = refs[(asset_id, kind)]
        print(f"  warning: {cls}.{prop} rbxassetid://{asset_id} not embedded: {error}", file=sys.stderr)
    if len(failures) > 12:
        print(f"  warning: {len(failures) - 12} additional unique assets failed", file=sys.stderr)
    opts.stats["asset_failures"] = len(failures)


def embed_downloaded_assets(inst, opts):
    if not opts.download_assets or opts.kine_version < 3:
        return
    for key, value, asset_id, kind in iter_asset_properties(inst, opts):
        result = opts.resolved_assets.get((asset_id, kind))
        if result is None or isinstance(result, Exception):
            continue  # Prefetch already warned once for each unique failure.
        data, ext = result
        if len(data) > MAX_ASSET_BYTES:
            raise ValueError("resolved asset exceeds the KINE per-asset size limit")
        asset_key = content_id(data)
        if asset_key in opts.mesh_assets:
            if opts.mesh_assets[asset_key] != data or kind != ASSET_MESH:
                raise ValueError("asset hash collision with embedded CSG mesh")
        elif asset_key in opts.embedded_assets:
            previous = opts.embedded_assets[asset_key]
            if previous[2] != data or previous[1] != kind:
                raise ValueError("asset hash collision / incompatible asset kind")
        else:
            if len(opts.embedded_assets) + len(opts.mesh_assets) >= MAX_ASSET_COUNT:
                raise ValueError("KINE asset count limit exceeded")
            new_total = opts.embedded_asset_bytes + len(data)
            if new_total + sum(map(len, opts.mesh_assets.values())) > MAX_ASSET_TOTAL_BYTES:
                raise ValueError("KINE embedded asset size limit exceeded")
            authored = "rbxassetid://" + asset_id
            opts.embedded_assets[asset_key] = (authored + ext, kind, data)
            opts.embedded_asset_bytes = new_total
        inst.props[key] = enc_string(f"kineasset://{asset_key}")
        opts.stats["downloaded_assets"] += 1
        dprint(opts, f"embed {inst.cls}.{key}: rbxassetid://{asset_id} -> {asset_key}")


# ---------------------------------------------------------------------------
# RBXM parsing
# ---------------------------------------------------------------------------
def read_chunks(data):
    if data[:8] != b"<roblox!":
        if data.lstrip()[:8] == b"<roblox ":
            raise ValueError("this is an XML .rbxmx file; only the binary format is supported")
        raise ValueError("not a Roblox binary file")
    if data[8:14] != b"\x89\xff\r\n\x1a\n":
        raise ValueError("corrupt header")
    pos = 32
    while pos + 16 <= len(data):
        name = data[pos:pos + 4]
        clen, ulen = struct.unpack_from("<II", data, pos + 4)
        pos += 16
        if clen == 0:
            body = data[pos:pos + ulen]
            pos += ulen
        else:
            body = decompress(data[pos:pos + clen], ulen)
            pos += clen
        yield name, body
        if name == b"END\x00":
            return
PART_OPERATIONS = {"UnionOperation", "NegateOperation", "IntersectOperation"}
CSG_MESH_PROPERTIES = {"MeshData", "MeshData2"}
CSG_XOR_KEY = bytes.fromhex("562e6e583120300434690c770c015e001a6037691d522b074f24596553047a")
def decode_csg_mesh(payload):
    """Read indexed geometry and authored vertex attributes from a Roblox CSGMDL."""
    if not payload.startswith(b"CSGMDL") and payload[:6] == b"\x15\x7d\x29\x15\x75\x6c":
# CSGMDL5 obfuscates only its header. Earlier versions use the same
# repeating key over the entire record.
        header = bytes(value ^ CSG_XOR_KEY[i] for i, value in enumerate(payload[:10]))
        if header[6:10] == b"\x05\0\0\0":
            payload = header + payload[10:]
        else:
            payload = bytes(value ^ CSG_XOR_KEY[i % len(CSG_XOR_KEY)]
                            for i, value in enumerate(payload))
    b = Buf(payload)
    if b.take(6) != b"CSGMDL":
        raise ValueError("missing CSGMDL mesh header")
    version = b.u32()
    if version in (2, 3, 4):
        b.take(32)
        vertex_count, stride = b.u32(), b.u32()
        if stride != 84:
            raise ValueError(f"unsupported CSGMDL vertex size {stride}")
        records = list(struct.iter_unpack("<6f8x2f44x", b.take(vertex_count * stride)))
        vertices = [record[:3] for record in records]
        normals = [record[3:6] for record in records]
        uvs = [record[6:8] for record in records]
        index_count = b.u32()
        indices = struct.unpack(f"<{index_count}I", b.take(index_count * 4))
    elif version == 5:
        count = lambda: struct.unpack("<H", b.take(2))[0]
        vertices = list(struct.iter_unpack("<3f", b.take(count() * 12)))
        normal_count = count()
        packed_normals = b.take(b.u32())
        normals = []
        if normal_count == len(vertices) and len(packed_normals) == normal_count * 6:
# CSGMDL5 stores biased 16-bit components with signed wraparound.
            normals = [tuple((((value + 1) & 0xFFFF) - 32768) / 32767 for value in record)
                       for record in struct.iter_unpack("<3H", packed_normals)]
        b.take(count() * 4)  # colors
        b.take(count())  # dominant normal axes used for material projection
        uvs = list(struct.iter_unpack("<2f", b.take(count() * 8)))
        count()
        b.take(b.u32())  # packed tangents
        index_count = b.u32()
        encoded = iter(b.take(b.u32()))
        indices = []
        current = 0
        for _ in range(index_count):
            first = next(encoded, None)
            if first is None:
                raise ValueError("truncated CSGMDL index stream")
            if first < 64:
                delta = first
            elif first < 128:
                delta = first - 128
            else:
                hi, lo = next(encoded, None), next(encoded, None)
                if hi is None or lo is None:
                    raise ValueError("truncated CSGMDL index delta")
                delta = ((first - 128) << 16) | (hi << 8) | lo
            current = (current + delta) & 0x7FFFFF
            indices.append(current)
        marker_count = b.u8()
        markers = struct.unpack(f"<{marker_count}I", b.take(marker_count * 4))
        if len(markers) < 2 or list(markers) != sorted(markers) or markers[-1] > len(indices):
            raise ValueError("invalid CSGMDL face ranges")
        indices = indices[markers[0]:markers[1]]
    else:
        raise ValueError(f"unsupported CSGMDL version {version}")
    if not vertices or not indices or len(indices) % 3 or max(indices) >= len(vertices):
        raise ValueError("invalid CSGMDL triangles")
    if any(not math.isfinite(value) for vertex in vertices for value in vertex):
        raise ValueError("nonfinite CSGMDL vertex")
    if len(normals) != len(vertices) or any(not all(map(math.isfinite, normal)) for normal in normals):
        normals = []
    if len(uvs) != len(vertices) or any(not all(map(math.isfinite, uv)) for uv in uvs):
        uvs = []
    return vertices, indices, normals, uvs
def import_csg_mesh(inst, opts):
    payload = inst.props.pop("MeshData2", None) or inst.props.get("MeshData")
    for prop in ("MeshData", "ChildData", "ChildData2", "PhysicsData", "PhysicalConfigData",
                 "AeroMeshData", "SolidMeshHolder", "InitialSize", "AssetId"):
        inst.props.pop(prop, None)
    if not payload:
        if inst.cls != "NegateOperation":
            raise ValueError(f"{inst.name!r}: union has no embedded mesh")
        return
    if opts.kine_version < 3:
        raise ValueError("importing unions requires KINE version 3 or newer")
    vertices, indices, normals, uvs = decode_csg_mesh(payload)
    axes = tuple(zip(*vertices))
    minima = tuple(map(min, axes))
    maxima = tuple(map(max, axes))
    centers = [(low + high) * 0.5 for low, high in zip(minima, maxima)]
    halves = [(high - low) * 0.5 for low, high in zip(minima, maxima)]
    obj = []
    for vertex in vertices:
        point = [(value - center) / half if half > 0 else 0
                 for value, center, half in zip(vertex, centers, halves)]
        obj.append("v {:.9g} {:.9g} {:.9g}\n".format(*point))
# Positions are divided by the half extents. Normals use the inverse
# transpose so the engine's per-axis instance scale restores their direction.
    normalized = []
    for normal in normals:
        scaled = tuple(value * half for value, half in zip(normal, halves))
        length = math.hypot(*scaled)
        if length == 0:
            normalized = []
            break
        normalized.append(tuple(value / length for value in scaled))
    for normal in normalized:
        obj.append("vn {:.9g} {:.9g} {:.9g}\n".format(*normal))
    for uv in uvs:
        obj.append("vt {:.9g} {:.9g}\n".format(*uv))
    corners = []
    for i in range(1, len(vertices) + 1):
        if normalized:
            corners.append(f"{i}/{i}/{i}" if uvs else f"{i}//{i}")
        else:
            corners.append(f"{i}/{i}" if uvs else str(i))
    for i in range(0, len(indices), 3):
        obj.append("f {} {} {}\n".format(*(corners[index] for index in indices[i:i + 3])))
    data = "".join(obj).encode("ascii")
    key = 14695981039346656037
    for byte in data:
        key = ((key ^ byte) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    key = f"{((key ^ len(data)) * 1099511628211) & 0xFFFFFFFFFFFFFFFF:016x}"
    if key in opts.mesh_assets and opts.mesh_assets[key] != data:
        raise ValueError("embedded mesh hash collision")
    opts.mesh_assets[key] = data
    inst.props["MeshId"] = enc_string(f"kineasset://{key}")
    opts.stats["imported_unions"] += 1
def parse_rbxm(data, opts):
    classes = {}  # class id -> (name, [refs])
    insts = {}
    unmapped_enum = opts.stats["unmapped_enums"]
    unsupported = opts.stats["unsupported_types"]
    parents = []
    shared_strings = []
    for name, body in read_chunks(data):
        b = Buf(body)
        if name == b"SSTR":
            b.u32()
            for _ in range(b.u32()):
                b.take(16)
                shared_strings.append(b.string())
        elif name == b"INST":
            cid = b.u32()
            cname = b.string().decode("utf-8", "replace")
            fmt = b.u8()
            count = b.u32()
            refs = b.refs(count)
            services = [False] * count
            if fmt == 1:
                services = [x != 0 for x in b.take(count)]
            classes[cid] = (cname, refs)
            for r, s in zip(refs, services):
                inst = Inst(opts.aliases.get(cname, cname), r, s)
                if inst.cls == "Part" and cname in PRIMITIVE_SHAPES:
                    inst.props["Shape"] = enc_enum("PartType", PRIMITIVE_SHAPES[cname])
                insts[r] = inst
        elif name == b"PROP":
            cid = b.u32()
            pname = b.string().decode("utf-8", "replace")
            t = b.u8()
            if cid not in classes:
                continue
            cname, refs = classes[cid]
            ref_property = REFERENCE_PROPERTIES.get(cname, {}).get(pname)
            if t == 0x13 and ref_property:
                if opts.kine_version >= 8:
                    for ref, target in zip(refs, b.refs(len(refs))):
                        insts[ref].props[ref_property] = target
                continue
            if cname in PART_OPERATIONS and pname in CSG_MESH_PROPERTIES:
                values = ([shared_strings[index] for index in b.raw_u32s(len(refs))]
                          if t == 0x1C else [b.string() for _ in refs] if t == 1 else None)
                if values is not None:
                    for ref, value in zip(refs, values):
                        insts[ref].props[pname] = value
                    continue
            key = ("Shape" if pname == "shape" and cname in {"Part", "Seat", "VehicleSeat"}
                   else PROP_RENAMES.get(pname, pname))
            enum_name = (opts.enum_map.get(cname + "." + pname)
                         or opts.enum_map.get(pname)
                         or opts.enum_map.get(key))
            try:
                vals = decode_prop(t, b, len(refs), enum_name)
            except (ValueError, struct.error, IndexError) as e:
                print("  warning: %s.%s (type %#x) failed to decode: %s" % (cname, pname, t, e), file=sys.stderr)
                continue
            if vals is None:
                if t == 0x12 and enum_name is None:
                    unmapped_enum.add(cname + "." + pname)
                elif t != 0x12:
                    unsupported[t] = unsupported.get(t, 0) + 1
                continue
            for ref, v in zip(refs, vals):
                if v is None:
                    continue
                inst = insts[ref]
                tag, val = v
                if tag == "s":
                    if pname == "Name":
                        inst.name = val
                    elif pname == "AttributesSerialize":
                        kept = []
                        for key_bytes, value_bytes in parse_attributes(val):
                            if attribute_name_is_valid(key_bytes):
                                kept.append((key_bytes, value_bytes))
                            else:
                                opts.stats["dropped_attributes"] += 1
                                dprint(
                                    opts,
                                    "drop attribute %r of %s %r: name the engine rejects"
                                    % (key_bytes.decode("utf-8", "replace"), inst.cls, inst.name),
                                )
                        inst.attrs = kept
                    elif pname == "Tags" and not val:
                        pass
                    else:
                        inst.props[key] = enc_string(val)
                elif tag == "b":
                    if pname == "Archivable":
                        inst.archivable = val
                    else:
                        inst.props[key] = enc_bool(val)
                else:
                    inst.props[key] = val
        elif name == b"PRNT":
            b.u8()
            count = b.u32()
            children = b.refs(count)
            pars = b.refs(count)
            parents = list(zip(children, pars))
    for child, par in parents:
        c = insts.get(child)
        if c is None:
            continue
        p = insts.get(par)
        if p is not None:
            c.parent = p
            p.children.append(c)
# A Part's BrickColor would overwrite its exact Color if applied after it.
    for inst in insts.values():
        if "Color" in inst.props and "BrickColor" in inst.props:
            del inst.props["BrickColor"]
    roots = [i for i in insts.values() if i.parent is None]
    roots.sort(key=lambda i: i.ref)
    return roots
# ---------------------------------------------------------------------------
# KINE writing
# ---------------------------------------------------------------------------
_uid_index = [0]
def keep(inst, opts):
    if opts.kine_version < 8 and inst.cls in REFERENCE_PROPERTIES:
        record_drop(opts, inst, "constraint endpoints require KINE version 8")
        return False
    if inst.cls in opts.drop_classes:
        record_drop(opts, inst, "drop-class")
        return False
    if opts.allowed_classes is not None and inst.cls not in opts.allowed_classes:
        record_drop(opts, inst, "class not in allowed list")
        return False
    dprint(opts, "keep  %s %r subtree=%d" % (inst.cls, inst.name, subtree_size(inst)))
    return True
def encode_instance(inst, opts, out, indices, references):
    if inst.cls in PART_OPERATIONS:
        import_csg_mesh(inst, opts)
    kids = [child for child in inst.children if keep(child, opts)]
    embed_downloaded_assets(inst, opts)
    opts.stats["kept_instances"] += 1
    if inst.ref >= 0:
        indices[inst.ref] = opts.stats["kept_instances"]
    if inst.is_service:
        opts.stats["services"].append(inst.name.decode("utf-8", "replace") if isinstance(inst.name, bytes) else inst.name)
    props = [(k, v) for k, v in inst.props.items() if k not in opts.drop_props and (inst.cls + "." + k) not in opts.drop_props]
    _uid_index[0] += 1
    out += kstr(inst.cls)
    out += kstr(inst.name)
    out.append(1 if inst.archivable else 0)
    out += struct.pack("<qII", random.getrandbits(63), int(time.time()) & 0xFFFFFFFF, _uid_index[0])
    out += struct.pack("<I", len(props))
    for key, value in props:
        out += kstr(key)
        if isinstance(value, int):
            out.append(TAG_INSTANCE_REF)
            references.append((len(out), value))
            out += b"\0" * 4
        else:
            out += value
            if opts.kine_version >= 5 and value[:3] == bytes((TAG_USERDATA, DT_FONT, 0)):
                out.append(0)
    out += struct.pack("<I", len(inst.attrs))
    for k, v in inst.attrs:
        out += kstr(k) + v
    out += struct.pack("<I", len(kids))
    for child in kids:
        encode_instance(child, opts, out, indices, references)
def build_root(roots, opts, root_name):
    dprint(opts, "roots found in source: %d" % len(roots))
    for r in roots:
        dprint(opts, "  root class=%s name=%r is_service=%s subtree=%d" % (r.cls, r.name, r.is_service, subtree_size(r)))
    roots = [r for r in roots if keep(r, opts)]
    if len(roots) == 1 and not roots[0].is_service:
        dprint(opts, "root is a single non-service %s, using it directly" % roots[0].cls)
        return roots[0]
    wrapper = Inst("DataModel" if any(r.is_service for r in roots) else opts.root_class, -1)
    wrapper.name = root_name
    wrapper.children = roots
    dprint(opts, "root is DataModel wrapper with %d service children" % len(roots))
    return wrapper
def write_kine(root, opts):
    tree, indices, references = bytearray(), {}, []
    encode_instance(root, opts, tree, indices, references)
    for offset, ref in references:
        struct.pack_into("<I", tree, offset, indices.get(ref, 0))
    out = bytearray(KINE_MAGIC)
    out.append(opts.kine_version)
    if opts.kine_version >= 3:
        out += struct.pack("<I", len(opts.mesh_assets) + len(opts.embedded_assets))
        for key, mesh in opts.mesh_assets.items():
            out += kstr(key) + kstr(key + ".obj") + bytes([ASSET_MESH]) + kstr(mesh)
        for key, (original_path, kind, payload) in opts.embedded_assets.items():
            out += kstr(key) + kstr(original_path) + bytes([kind]) + kstr(payload)
    out += tree
    if opts.kine_version >= 4:
        out.append(0)  # no terrain
    return bytes(out), opts.stats["kept_instances"]
def convert(path, out_path, opts):
    with open(path, "rb") as f:
        data = f.read()
    opts.stats["kept_instances"] = 0
    opts.stats["dropped_instances"] = 0
    opts.stats["dropped_attributes"] = 0
    opts.stats["services"] = []
    opts.stats["imported_unions"] = 0
    opts.mesh_assets.clear()
    opts.embedded_assets.clear()
    opts.resolved_assets.clear()
    opts.embedded_asset_bytes = 0
    opts.stats["downloaded_assets"] = 0
    opts.stats["asset_failures"] = 0
    roots = parse_rbxm(data, opts)
    stem = os.path.splitext(os.path.basename(path))[0]
    root = build_root(roots, opts, stem)
    prefetch_assets(root, opts)
    blob, count = write_kine(root, opts)
    with open(out_path, "wb") as f:
        f.write(blob)
    print("%s -> %s  (%d instances, %d bytes, %d unions)" %
          (path, out_path, count, len(blob), opts.stats["imported_unions"]))
    if opts.debug or opts.download_assets:
        print_summary(opts)
def print_summary(opts):
    s = opts.stats
    print("kept instances: %d" % (s["kept_instances"]))
    print("dropped instances: %d" % s["dropped_instances"])
    print("imported unions: %d (%d unique meshes)" % (s["imported_unions"], len(opts.mesh_assets)))
    print("embedded Roblox asset properties: %d (%d unique payloads), failed unique IDs: %d" % (s["downloaded_assets"], len(opts.embedded_assets), s["asset_failures"]))
    print("services written: %s" % (", ".join(s["services"]) if s["services"] else "(none)"))
    print("dropped attributes: %d" % s["dropped_attributes"])
def main():
    ap = argparse.ArgumentParser(description="Convert Roblox .rbxm/.rbxl to Kinemium .kine")
    ap.add_argument("inputs", nargs="+", help=".rbxm/.rbxl files or directories")
    ap.add_argument("-o", "--output", help="output file (single input) or directory")
    ap.add_argument("--kine-version", type=int, choices=(2, 3, 4, 8), default=8)
    ap.add_argument("--root-class", default="Model", help="wrapper class when the file has several top-level instances")
    ap.add_argument("--classes-file", help="replace the built-in class list with this file (one class name per line)")
    ap.add_argument("--allow-class", action="append", default=[], help="add a class to the allowed list; repeatable")
    ap.add_argument("--alias", action="append", default=[], help="Old=New class substitution, e.g. WedgePart=Part; repeatable")
    ap.add_argument("--no-class-filter", action="store_true", help="keep every class (the loader fails on unknown ones)")
    ap.add_argument("--debug", action="store_true", help="print per-instance keep/drop decisions and a summary")
    ap.add_argument("--no-download-assets", action="store_true", help="keep rbxassetid:// references unchanged (default: download + embed)")
    ap.add_argument("--asset-timeout", type=float, default=8.0, help="timeout per Roblox network request (default 8s)")
    ap.add_argument("--asset-retries", type=int, default=1, help="retry transient network errors (default 1)")
    ap.add_argument("--asset-workers", type=int, default=4, help="parallel asset download workers (default 4)")
    ap.add_argument("--asset-cache-dir", help="optional directory for persistent, credential-free raw asset byte cache")
    ap.add_argument("--drop-class", action="append", default=[], help="class to remove (with subtree); repeatable")
    ap.add_argument("--drop-prop", action="append", default=[], help="property or Class.Property to remove; repeatable")
    ap.add_argument("--enum-values", help="JSON {\"Material\": {\"Plastic\": 1, ...}} giving Kinemium's item values, so enums are converted by name")
    ap.add_argument("--enum-map", help="JSON file mapping Prop or Class.Prop to an enum type name")
    args = ap.parse_args()
    opts = Options()
    opts.kine_version = args.kine_version
    opts.root_class = args.root_class
    opts.debug = args.debug
    opts.download_assets = not args.no_download_assets and opts.kine_version >= 3
    opts.asset_workers = max(1, min(args.asset_workers, 16))
    if args.kine_version == 2 and not args.no_download_assets:
        print("warning: KINE v2 has no asset table; preserving rbxassetid:// references", file=sys.stderr)
    opts.downloader = RobloxDownloader(
        api_key=os.environ.get("ROBLOX_API_KEY", "").strip(),
        cookie=os.environ.get("ROBLOSECURITY", "").strip(),
        timeout=max(1.0, args.asset_timeout),
        retries=max(0, min(args.asset_retries, 5)),
        cache_dir=args.asset_cache_dir,
    )
    if opts.download_assets and not opts.downloader.api_key and not opts.downloader.cookie:
        print("warning: no Roblox credentials supplied; asset delivery commonly requires "
              "ROBLOX_API_KEY or ROBLOSECURITY environment variable", file=sys.stderr)
    opts.drop_classes = set(args.drop_class)
    opts.drop_props |= set(args.drop_prop)
    if args.classes_file:
        with open(args.classes_file) as f:
            opts.allowed_classes = {l.strip() for l in f if l.strip() and not l.startswith("#")}
    for a in args.alias:
        old, _, new = a.partition("=")
        opts.aliases[old] = new
    if args.no_class_filter:
        opts.allowed_classes = None
    elif opts.allowed_classes is not None:
        opts.allowed_classes.update(args.allow_class)
    if args.enum_map:
        with open(args.enum_map) as f:
            opts.enum_map.update(json.load(f))
    if args.enum_values:
        with open(args.enum_values) as f:
            build_enum_remap(json.load(f))
    files = []
    for p in args.inputs:
        if os.path.isdir(p):
            for fn in sorted(os.listdir(p)):
                if fn.lower().endswith((".rbxm", ".rbxl")):
                    files.append(os.path.join(p, fn))
        else:
            files.append(p)
    if not files:
        sys.exit("no input files")
    single_file_out = args.output and len(files) == 1 and not args.output.endswith(("/", "\\")) and not os.path.isdir(args.output)
    if args.output and not single_file_out:
        os.makedirs(args.output, exist_ok=True)
    failures = 0
    for f in files:
        if single_file_out:
            out = args.output
        else:
            name = os.path.splitext(os.path.basename(f))[0] + ".kine"
            out = os.path.join(args.output or os.path.dirname(f) or ".", name)
        try:
            convert(f, out, opts)
        except (ValueError, OSError, struct.error, IndexError) as e:
            failures += 1
            print("FAILED %s: %s" % (f, e), file=sys.stderr)
    s = opts.stats
    if s["dropped_classes"]:
        print("dropped classes: " + ", ".join("%s x%d" % kv for kv in sorted(s["dropped_classes"].items())))
    if s["unmapped_enums"]:
        print("dropped enum properties with no enum name (use --enum-map): " + ", ".join(sorted(s["unmapped_enums"])))
    if s["unsupported_types"]:
        print("skipped properties of unsupported types: " + ", ".join("%#x x%d" % kv for kv in sorted(s["unsupported_types"].items())))
    sys.exit(1 if failures else 0)
if __name__ == "__main__":
    main()

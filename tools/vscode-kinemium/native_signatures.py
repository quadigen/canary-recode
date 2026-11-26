"""Kinemium Luau signatures from Odin native binding implementations.

The generic extractor only emits parameters for explicit VM argument reads. API
specific entries are source-verified, not inherited from Roblox documentation.
Unknown native calls retain a conservative vararg fallback.
"""
from __future__ import annotations
import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Signature:
    params: str
    returns: str = 'any'
    description: str = ''


GPU_TYPES = '''-- GPUCompute resource/descriptor tables, reflected from GPUCompute*.odin.
type GPUComputeLayout = number | {[number]: "StorageBuffer" | "UniformBuffer" | "SampledTexture" | "StorageTexture"}
type GPUComputeTextureOptions = {
    Width: number?, Height: number?, Depth: number?, Layers: number?,
    Dimension: ("1D" | "2D" | "3D" | "2DArray")?,
    Format: ("RGBA8" | "RGBA8_SRGB" | "R8" | "RG8" | "R32F" | "RG32F" | "RGBA16F" | "RGBA32F" | "R32UI")?,
    Usage: {string}?, Storage: boolean?, GenerateMipmaps: boolean?,
    Filter: ("Linear" | "Nearest")?, AddressMode: ("Repeat" | "ClampToEdge")?,
    ColorSpace: ("Linear" | "SRGB")?,
}
type GPUComputeTextureInfo = {
    Width: number, Height: number, Depth: number, Layers: number,
    MipLevels: number, Format: string, Dimension: string, Storage: boolean,
}
type GPUComputeMeshData = {
    Vertices: buffer, Indices: buffer, VertexCount: number, IndexCount: number,
    TriangleCount: number, VertexStride: number,
}
type GPUComputeBVH = {Nodes: buffer, Triangles: buffer, NodeCount: number, TriangleCount: number}
type GPUComputeTaskInfo = {Queue: number, DispatchCount: number, Complete: boolean}
type GPUComputeWarmupResult = {Ticket: number, Pipeline: number?, Error: string?}
type GPUComputeCacheStats = {
    Hits: number, Misses: number, Writes: number, CorruptEntries: number,
    CompileNanoseconds: number, DirectTextureDispatches: number,
    DirectTextureBytes: number, PixelReadbackBytes: number, PixelUploadBytes: number,
}
type GPUComputeCapabilities = {
    DeviceName: string, MaxBufferSize: number, MaxUniformBufferSize: number,
    MaxTextureSize: number, MaxTextureSize1D: number, MaxTextureSize3D: number,
    MaxTextureLayers: number, SharedMemorySize: number,
    MaxWorkgroupInvocations: number, MaxBindings: number,
    ComputeQueueCount: number, MaxPendingTasks: number,
    ParallelQueues: boolean, TimelineSemaphores: boolean,
    MaxWorkgroupSize: {number}, MaxWorkgroupCount: {number},
    Float64: boolean, Int64: boolean, Int16: boolean,
    ExtendedStorageFormats: boolean, SampledTextures: boolean,
    DescriptorIndexing: boolean, RayQuery: boolean,
}
type GPUComputeMaterialTextures = {
    Albedo: number?, Normal: number?, RoughnessMap: number?, MetallicMap: number?,
    ORM: number?, Height: number?, AO: number?, Emissive: number?,
    Roughness: number, Metallic: number, UVScale: number, HeightScale: number,
}
'''

# Name, parameters, Luau return pack, documentation. Source: GPUCompute.odin,
# GPUComputeResources.odin, GPUComputeRender.odin (Nov 22, 2026).
GPU_METHODS = {
    'IsSupported': Signature('', '(boolean, string?)', 'Opens the compute device if supported; returns success and an optional error.'),
    'Dispatch': Signature('operation: "Add" | "Subtract" | "Multiply" | "MatrixMultiply" | "Divide" | "Min" | "Max" | "Abs" | "Negate" | "Sqrt", a: buffer, b: buffer?, rows: number?, inner: number?, columns: number?', '(boolean, string?)', 'Dispatches float32 buffer arithmetic. MatrixMultiply requires rows, inner, and columns; Abs/Negate/Sqrt use only a.'),
    'Poll': Signature('', '(buffer?, string?)', 'Polls a completed arithmetic dispatch and returns the resulting float32 buffer.'),
    'CompileShader': Signature('source: string, layout: GPUComputeLayout', '(boolean, string?)', 'Compiles a compute shader against a binding count or descriptor layout.'),
    'CreatePipeline': Signature('source: string, layout: GPUComputeLayout', '(number?, string?)', 'Creates a compute shader pipeline; returns its ID on success.'),
    'QueuePipeline': Signature('source: string, layout: GPUComputeLayout', '(number?, string?)', 'Queues shader pipeline warmup and returns its ticket (maximum 16 queued jobs).'),
    'WarmupPipelines': Signature('limit: number?', '{GPUComputeWarmupResult}', 'Compiles up to four queued pipelines with a cooperative time budget.'),
    'GetWarmupPendingCount': Signature('', 'number', 'Returns the number of queued pipeline warmup jobs.'),
    'GetCacheStats': Signature('', 'GPUComputeCacheStats', 'Reads shader, direct texture dispatch, upload, and readback counters.'),
    'DispatchTexture': Signature('material: MaterialVariant, samplerName: string, shaderSource: string, width: number, height: number', '(boolean?, string?)', 'Writes directly to a compiled MaterialVariant sampler using a shared Vulkan renderer; returns nil and an error when unavailable.'),
    'CreateBuffer': Signature('sizeBytes: number', '(number?, string?)', 'Allocates a native device buffer and returns its ID.'),
    'AllocateDeviceBuffer': Signature('sizeBytes: number', '(number?, string?)', 'Alias of CreateBuffer.'),
    'WriteBuffer': Signature('bufferId: number, data: buffer, offsetBytes: number?', '(boolean, string?)', 'Writes a Luau buffer to a native device buffer.'),
    'ReadBuffer': Signature('bufferId: number, offsetBytes: number?, sizeBytes: number?', '(buffer?, string?)', 'Reads bytes from a native device buffer.'),
    'BindBuffer': Signature('binding: number, dataOrBufferId: buffer | number', '(boolean, string?)', 'Binds a native buffer ID or a retained Luau buffer to a shader binding.'),
    'UnbindBuffer': Signature('binding: number', '(boolean, string?)', 'Unbinds the buffer or texture at a shader binding.'),
    'UploadBuffer': Signature('data: buffer', '(boolean, string?)', 'Uploads an already-bound Luau buffer to its associated GPU allocation.'),
    'DownloadBuffer': Signature('data: buffer', '(boolean, string?)', 'Downloads GPU data into a previously bound Luau buffer.'),
    'ReleaseBuffer': Signature('data: buffer', '(boolean, string?)', 'Releases a retained/bound Luau buffer and associated GPU resource.'),
    'DestroyBuffer': Signature('bufferId: number', '(boolean, string?)', 'Destroys a device buffer by ID (for Luau buffers use ReleaseBuffer).'),
    'UsePipeline': Signature('pipelineId: number', '(boolean, string?)', 'Selects a previously created compute pipeline.'),
    'DestroyPipeline': Signature('pipelineId: number', '(boolean, string?)', 'Destroys a previously created compute pipeline.'),
    'BeginCommands': Signature('', '(boolean, string?)', 'Begins a command recording batch.'),
    'SubmitCommands': Signature('', '(boolean, string?)', 'Submits the recorded command batch.'),
    'CancelCommands': Signature('', '(boolean, string?)', 'Cancels the current recorded command batch.'),
    'MemoryBarrier': Signature('', '(boolean, string?)', 'Inserts a device command memory barrier.'),
    'CopyGPUBuffer': Signature('source: buffer | number, destination: buffer | number, sizeBytes: number?, sourceOffsetBytes: number?, destinationOffsetBytes: number?', '(boolean, string?)', 'Copies between native buffers or retained Luau GPU buffers.'),
    'FillGPUBuffer': Signature('dataOrBufferId: buffer | number, value: number, sizeBytes: number?, offsetBytes: number?', '(boolean, string?)', 'Fills a GPU buffer with a uint32 value.'),
    'SetPushConstants': Signature('bytes: buffer', '(boolean, string?)', 'Sets push constant bytes for the active compute pipeline.'),
    'DispatchShader': Signature('x: number, y: number?, z: number?', '(boolean, string?)', 'Dispatches workgroups to the currently selected pipeline.'),
    'SubmitTask': Signature('x: number, y: number?, z: number?', '(number?, string?)', 'Submits an asynchronous compute dispatch and returns the task ID.'),
    'BeginTask': Signature('', '(boolean, string?)', 'Begins a deferred compute task command batch.'),
    'SubmitTaskBatch': Signature('', '(number?, string?)', 'Submits the active deferred compute task batch.'),
    'PollTask': Signature('taskId: number', '(boolean, string?)', 'Checks whether the specified asynchronous compute task has completed.'),
    'GetTaskInfo': Signature('taskId: number', '(GPUComputeTaskInfo?, string?)', 'Reads queue index, dispatch count, and completion state.'),
    'GetPendingTaskCount': Signature('', 'number', 'Returns the number of pending asynchronous GPU tasks.'),
    'PollShader': Signature('', '(boolean, string?)', 'Checks the active asynchronous shader dispatch.'),
    'CreateTexture': Signature('optionsOrWidth: GPUComputeTextureOptions | number, heightOrPixels: number | buffer?, pixelsOrOptions: buffer | GPUComputeTextureOptions?, options: GPUComputeTextureOptions?', '(number?, string?)', 'Creates a native GPU texture from a descriptor table, or from width, height, pixel buffer and options.'),
    'LoadTexture': Signature('source: Content | Image | buffer | string, options: GPUComputeTextureOptions?', '(number?, string?)', 'Loads a GPU texture from an Image instance, encoded buffer, content URI, or path.'),
    'GetTextureInfo': Signature('textureId: number', '(GPUComputeTextureInfo?, string?)', 'Reads texture dimensions, format, and storage usage.'),
    'BindTexture': Signature('binding: number, textureId: number', '(boolean, string?)', 'Binds a texture to a shader binding.'),
    'DestroyTexture': Signature('textureId: number', '(boolean, string?)', 'Destroys a native texture.'),
    'GetMaterialTextures': Signature('material: MaterialVariant | EnumMaterial, options: GPUComputeTextureOptions?', '(GPUComputeMaterialTextures?, string?)', 'Creates texture handles and material parameters for a MaterialVariant or Enum.Material.'),
    'LoadMesh': Signature('source: Content | string, meshIndex: number?', '(GPUComputeMeshData?, string?)', 'Loads mesh vertex/index buffers from Content or asset path.'),
    'GetMeshFromInstance': Signature('mesh: MeshPart | EditableMesh', '(GPUComputeMeshData?, string?)', 'Extracts mesh data from an accessible MeshPart or EditableMesh.'),
    'BuildBVH': Signature('mesh: GPUComputeMeshData, options: {MaxLeafTriangles: number?}?', '(GPUComputeBVH?, string?)', 'Builds a BVH for the mesh vertex and index buffers.'),
    'GetCapabilities': Signature('', '(GPUComputeCapabilities?, string?)', 'Returns compute device feature limits and supported formats; may fail with an error.'),
}

# Carefully checked method signatures from Object_Namecall in Object.odin and
# Part2D_namecall in Part2D.odin. The latter exposes actual Vector2 input.
CLASS_METHOD_OVERRIDES: dict[str, dict[str, Signature]] = {
    'Instance': {
        'Clone': Signature('', 'Instance?', 'Returns a copy if Archivable, otherwise nil.'),
        'Destroy': Signature('', '()', 'Destroys the instance and its descendants.'),
        'FindFirstChild': Signature('name: string, recursive: boolean?', 'Instance?', 'Finds a child by name.'),
        'FindFirstDescendant': Signature('name: string', 'Instance?', 'Finds the first accessible descendant with this name.'),
        'ClearAllChildren': Signature('', '()', 'Destroys the instance children.'),
        'ContainsPoint': Signature('x: number, y: number', 'boolean', 'Checks whether the GuiObject contains a point.'),
    },
    'Part2D': {
        'ApplyImpulse': Signature('impulse: Vector2', '()', 'Adds a physics impulse, evaluated on the next simulation step.'),
        'ApplyAngularImpulse': Signature('impulse: number', '()', 'Adds angular impulse.'),
    },
    'GPUCompute': GPU_METHODS,
}

DATATYPE_METHOD_OVERRIDES: dict[str, dict[str, Signature]] = {
    'Vector3': {
        'Dot': Signature('other: Vector3', 'number', 'Returns the dot product of two 3D vectors.'),
        'Cross': Signature('other: Vector3', 'Vector3', 'Returns the cross product.'),
        'Lerp': Signature('other: Vector3, alpha: number', 'Vector3', 'Linearly interpolates toward other.'),
        'Angle': Signature('other: Vector3, axis: Vector3?', 'number', 'Computes an angle in radians, optionally about an axis.'),
        'FuzzyEq': Signature('other: Vector3, epsilon: number?', 'boolean', 'Compares components within a tolerance.'),
        'Abs': Signature('', 'Vector3'),
        'Ceil': Signature('', 'Vector3'),
        'Floor': Signature('', 'Vector3'),
        'Sign': Signature('', 'Vector3'),
        'Max': Signature('...: Vector3', 'Vector3'),
        'Min': Signature('...: Vector3', 'Vector3'),
    },
}

# Recognized Lua VM argument APIs. A position must be a direct integer literal;
# dynamic indices cannot be typed safely from syntax alone.
ARG_CALLS = re.compile(
    r'\b(?:vm\.)?Arg(?P<optional>Optional)?(?P<typ>Number|Integer|String|Boolean|Buffer|Vector3|Vector2)\s*\(\s*L\s*,\s*(?P<index>\d+)\s*'
    r'|\bdatatypes\.Arg_(?P<dt>[A-Za-z_]\w*)\s*\(\s*L\s*,\s*(?P<dtindex>\d+)\s*'
    r'|\benums\.Arg_Item\s*\(\s*L\s*,\s*(?P<enindex>\d+)\s*,\s*\w+\s*,\s*"(?P<enum>\w+)"',
    re.MULTILINE,
)


def infer_method_signature(method: str, body: str, first_index: int = 2) -> Signature:
    """Infer only explicitly read parameter indices and concrete VM types."""
    by_position: dict[int, tuple[str, bool, str]] = {}
    for match in ARG_CALLS.finditer(body):
        position = int(match.group('index') or match.group('dtindex') or match.group('enindex'))
        if position < first_index or position > 24:
            continue
        kind = match.group('dt') or (('Enum' + match.group('enum')) if match.group('enum') else '')
        if not kind:
            kind = {'Number':'number','Integer':'number','String':'string','Boolean':'boolean','Buffer':'buffer',
                    'Vector2':'Vector2','Vector3':'Vector3'}[match.group('typ')]
        opt = bool(match.group('optional'))
        # If the source checks for nil before reading the argument, it is optional.
        if re.search(r'vm\.IsNoneOrNil\s*\(\s*L\s*,\s*' + str(position) + r'\s*[,)]', body):
            opt = True
        prefix = body[max(0, match.start() - 90):match.start()]
        names = re.search(r'([A-Za-z_][A-Za-z_0-9]*)\s*:?=\s*(?:(?:[A-Za-z_]\w*\.)?\w+\s*\(\s*){0,3}$', prefix)
        name = names.group(1) if names else f'arg{position - first_index + 1}'
        if name in ('L','value','result','object','args','data'):
            name = f'arg{position - first_index + 1}'
        previous = by_position.get(position)
        if previous:
            # Multiple possible types for an index: preserve a union rather
            # than asserting the last branch is the only valid input.
            old, old_opt, old_name = previous
            kind = ' | '.join(sorted(set(old.split(' | ') + kind.split(' | '))))
            opt = opt or old_opt
            if name.startswith('arg') and not old_name.startswith('arg'):
                name = old_name
        by_position[position] = (kind, opt, name)
    if not by_position:
        # With no argument reads, assume no required arguments, unless an opaque
        # delegated implementation might use its own arguments.
        # An unknown/delegated implementation may read parameters indirectly;
        # preserve flexible arguments instead of silently advertising no args.
        if not body or re.search(r'vm\.(?:StackTop|Arg|Check)|\b(namecall|invoke|dispatch)\s*\(', body, re.IGNORECASE):
            return Signature('...: any', 'any')
        return Signature('', 'any')
    params = []
    for i in range(first_index,max(by_position)+1):
        kind, optional, name = by_position.get(i, ('any', True, f'arg{i-first_index+1}'))
        if not re.match(r'^[A-Za-z_]\w*$',name): name=f'arg{i-first_index+1}'
        params.append(f'{name}: {kind}{"?" if optional and not kind.endswith("?") else ""}')
    return Signature(', '.join(params), 'any')

STATIC_DATATYPE_OVERRIDES: dict[str, dict[str, Signature]] = {
    'Vector3': {
        'FromAxis': Signature('axis: EnumAxis', 'Vector3', 'Creates a unit vector from Enum.Axis.'),
        'FromNormalId': Signature('face: EnumNormalId', 'Vector3', 'Creates a unit vector from Enum.NormalId.'),
    },
}

# Additional source-reviewed method families: LuaVector2.odin, LuaCFrame.odin,
# LuaColor3.odin, LuaUDim.odin, LuaUDim2.odin, LuaQuaternion.odin,
# LuaRandom.odin. Method parameters mirror each namecall's vm.Arg/require_*
# accesses and its count; nontrivial multiple-return functions name the pack.
DATATYPE_METHOD_OVERRIDES.update({
    'Vector2': {
        'Abs': Signature('', 'Vector2'), 'Ceil': Signature('', 'Vector2'),
        'Floor': Signature('', 'Vector2'), 'Sign': Signature('', 'Vector2'),
        'Cross': Signature('other: Vector2', 'number'),
        'Dot': Signature('other: Vector2', 'number'),
        'Angle': Signature('other: Vector2, signed: boolean?', 'number'),
        'FuzzyEq': Signature('other: Vector2, epsilon: number?', 'boolean'),
        'Lerp': Signature('other: Vector2, alpha: number', 'Vector2'),
        'Max': Signature('...: Vector2', 'Vector2'),
        'Min': Signature('...: Vector2', 'Vector2'),
    },
    'CFrame': {
        'Inverse': Signature('', 'CFrame'),
        'Lerp': Signature('goal: CFrame, alpha: number', 'CFrame'),
        'ToWorldSpace': Signature('...: CFrame', 'CFrame'),
        'ToObjectSpace': Signature('...: CFrame', 'CFrame'),
        'PointToWorldSpace': Signature('...: Vector3', 'Vector3'),
        'PointToObjectSpace': Signature('...: Vector3', 'Vector3'),
        'VectorToWorldSpace': Signature('...: Vector3', 'Vector3'),
        'VectorToObjectSpace': Signature('...: Vector3', 'Vector3'),
        'Orthonormalize': Signature('', 'CFrame'),
        'GetComponents': Signature('', 'any', 'Returns the 12 position and rotation matrix components.'),
        'components': Signature('', 'any', 'Alias of GetComponents.'),
        'ToEulerAngles': Signature('order: EnumRotationOrder?', 'any', 'Returns X, Y and Z rotation angles.'),
        'ToEulerAnglesXYZ': Signature('', 'any', 'Returns XYZ Euler angles.'),
        'ToEulerAnglesYXZ': Signature('', 'any', 'Returns YXZ Euler angles.'),
        'ToOrientation': Signature('', 'any', 'Returns three orientation angles.'),
        'ToAxisAngle': Signature('', '(Vector3, number)', 'Returns the rotation axis and angle.'),
        'FuzzyEq': Signature('other: CFrame, epsilon: number?', 'boolean'),
        'AngleBetween': Signature('other: CFrame', 'number'),
    },
    'Color3': {
        'Lerp': Signature('goal: Color3, alpha: number', 'Color3'),
        'lerp': Signature('goal: Color3, alpha: number', 'Color3'),
        'ToHSV': Signature('', '(number, number, number)'),
        'toHSV': Signature('', '(number, number, number)'),
        'ToRGB': Signature('', '(number, number, number)'),
        'toRGB': Signature('', '(number, number, number)'),
        'ToHex': Signature('', 'string'),
        'toHex': Signature('', 'string'),
        'FromHSV': Signature('hue: number, saturation: number, value: number', 'Color3'),
        'fromHSV': Signature('hue: number, saturation: number, value: number', 'Color3'),
        'FromRGB': Signature('red: number, green: number, blue: number', 'Color3'),
        'fromRGB': Signature('red: number, green: number, blue: number', 'Color3'),
        'GetLuminance': Signature('', 'number'),
        'GetContrastRatio': Signature('other: Color3', 'number'),
        'GetContrastingColor': Signature('...: Color3', 'Color3'),
    },
    'UDim': {
        'Lerp': Signature('goal: UDim, alpha: number', 'UDim'),
        'FuzzyEq': Signature('other: UDim, epsilon: number?', 'boolean'),
    },
    'UDim2': {
        'Lerp': Signature('goal: UDim2, alpha: number', 'UDim2'),
        'FuzzyEq': Signature('other: UDim2, epsilon: number?', 'boolean'),
    },
    'Quaternion': {
        'Conjugate': Signature('', 'Quaternion'),
        'Inverse': Signature('', 'Quaternion'),
        'Dot': Signature('other: Quaternion', 'number'),
        'Lerp': Signature('other: Quaternion, alpha: number', 'Quaternion'),
        'Slerp': Signature('other: Quaternion, alpha: number', 'Quaternion'),
        'ToAxisAngle': Signature('', '(Vector3, number)'),
    },
    'Random': {
        'Clone': Signature('', 'Random'),
        'NextInteger': Signature('minimum: number, maximum: number', 'number'),
        'NextNumber': Signature('minimum: number?, maximum: number?', 'number', 'Accepts either zero arguments or both minimum and maximum.'),
        'NextUnitVector': Signature('', 'Vector3'),
        'Shuffle': Signature('items: {any}', '()', 'Shuffles a table in place.'),
    },
})

CLASS_METHOD_OVERRIDES['Instance'].update({
    'GetChildren': Signature('', '{Instance}'),
    'GetDescendants': Signature('', '{Instance}'),
    'GetFullName': Signature('', 'string'),
    'WaitForChild': Signature('name: string, timeout: number?', 'Instance?', 'Returns nil after the optional timeout.'),
    'WaitForChildOfClass': Signature('className: string, timeout: number?', 'Instance?'),
    'FindFirstChildOfClass': Signature('className: string', 'Instance?'),
    'FindFirstChildWhichIsA': Signature('className: string, recursive: boolean?', 'Instance?'),
    'FindFirstAncestor': Signature('name: string', 'Instance?'),
    'FindFirstAncestorOfClass': Signature('className: string', 'Instance?'),
    'FindFirstAncestorWhichIsA': Signature('className: string', 'Instance?'),
    'GetAttribute': Signature('name: string', 'any'),
    'GetAttributes': Signature('', '{[string]: any}'),
    'SetAttribute': Signature('name: string, value: any', '()'),
    'GetAttributeChangedSignal': Signature('name: string', 'RBXScriptSignal'),
    'GetPropertyChangedSignal': Signature('name: string', 'RBXScriptSignal?'),
    'AddTag': Signature('tag: string', '()'),
    'RemoveTag': Signature('tag: string', '()'),
    'HasTag': Signature('tag: string', 'boolean'),
    'GetTags': Signature('', '{string}'),
    'IsA': Signature('className: string', 'boolean'),
    'IsAncestorOf': Signature('other: Instance', 'boolean'),
    'IsDescendantOf': Signature('other: Instance', 'boolean'),
})

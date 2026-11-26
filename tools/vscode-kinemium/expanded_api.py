"""Additional source-reviewed Luau API contracts for the Kinemium runtime.

No Roblox API dump is used. Contracts below are verified against the actual
classes/services Odin implementations, primarily *Namecall and *Get. An API
that is not implemented in Kinemium must not be added to this file.
"""
from native_signatures import Signature as S

EXTRA_TYPES = '''-- Native interfaces and tables that are returned from Kinemium services.
type KinemiumHttpRequest = {
    Url: string, Method: string?, Body: string?, Headers: {[string]: string}?,
}
type KinemiumHttpResponse = {
    Success: boolean, StatusCode: number, StatusMessage: string,
    Body: string, Headers: {[string]: string},
}
type KinemiumRaycast2DResult = {
    Instance: Part2D, Position: Vector2, Normal: Vector2, Distance: number,
}
-- DataStore, DataStoreKeyInfo and DataStorePages are independent native
-- userdata registered by DataStoreService, not classes constructible via Instance.
declare extern type DataStore with
    Name: string
    Scope: string
    function GetAsync(self, key: string): any
    function SetAsync(self, key: string, value: any): ()
    function UpdateAsync(self, key: string, transform: (any) -> any): any
    function RemoveAsync(self, key: string): any
    function IncrementAsync(self, key: string, delta: number?): number
    function GetVersionAsync(self, key: string, version: string): any
    function ListVersionsAsync(self, key: string, sortDirection: any?, minDate: number?, maxDate: number?, pageSize: number?): DataStorePages
    function RemoveVersionAsync(self, key: string, version: string): ()
    function GetSortedAsync(self, ascending: boolean?, pageSize: number?, minValue: number?, maxValue: number?): DataStorePages
end
declare extern type DataStoreKeyInfo with
    function GetMetadata(self): any
    function GetUserIds(self): any
end
declare extern type DataStorePages with
    function GetCurrentPage(self): {any}
    function AdvanceToNextPageAsync(self): ()
end
'''

# Source-checked property types. These override registered properties only;
# the generator never fabricates class members absent from native registration.
PROPERTY_OVERRIDES: dict[str, dict[str, str]] = {
    'Instance': {
        'Name': 'string', 'ClassName': 'string', 'Parent': 'Instance?',
        'Archivable': 'boolean', 'CanReplicate': 'boolean',
        'ReplicationGroup': 'string', 'ReplicationMode': 'EnumReplicationMode',
        'NetworkId': 'number', 'UniqueId': 'UniqueId',
        'Capabilities': 'SecurityCapabilities', 'Sandboxed': 'boolean',
        'IsInSandbox': 'boolean',
    },
    'Lighting': {'QualityPreset': 'EnumQualityPreset'},
    'Players': {'LocalPlayer': 'Player?'},
    'Player': {'Character': 'Model?', 'PlayerScripts': 'Instance?', 'PlayerGui': 'Instance?'},
    'Workspace': {
        'CurrentCamera': 'Camera?', 'Terrain': 'Terrain?',
        'Dimension': 'EnumDimension', 'FinishedReplicating': 'RBXScriptSignal',
    },
    'Workspace2D': {'Gravity': 'Vector2', 'BodyCount': 'number', 'ViewportSize': 'Vector2'},
    'Part': {
        'Shape': 'EnumPartType', 'Material': 'EnumMaterial',
        'AssemblyLinearVelocity': 'Vector3', 'Velocity': 'Vector3',
        'AssemblyAngularVelocity': 'Vector3', 'RotVelocity': 'Vector3',
    },
    'Model': {'PrimaryPart': 'Part?'},
    'Camera': {'CameraSubject': 'Instance?', 'CameraType': 'EnumCameraType'},
    'HttpService': {'HttpEnabled': 'boolean', 'AllowPrivateNetwork': 'boolean'},
}

# Method definitions are only applied when a class actually registers the
# specified method; Kinemium versions without the method are unaffected.
CLASS_METHODS: dict[str, dict[str, S]] = {
    'Players': {
        'GetPlayers': S('', '{Player}', 'Returns accessible Players service children.'),
        'GetPlayerByUserId': S('userId: number', 'Player?'),
        'GetPlayerFromCharacter': S('character: Model', 'Player?'),
    },
    'Player': {
        'DistanceFromCharacter': S('point: Vector3', 'number'),
        'LoadCharacter': S('', 'Model?'),
        'GetMouse': S('', 'Mouse'),
        'GetNetworkPing': S('', 'number'),
        'Teleport': S('destination: CFrame', '()'),
        'ApplyImpulse': S('impulse: Vector3', '()'),
    },
    'RunService': {
        'BindToRenderStep': S('name: string, priorityOrCallback: number | ((number) -> ()), callback: ((number) -> ())?', '()',
                              'Bind a render-step callback; priority may be omitted.'),
        'UnbindFromRenderStep': S('name: string', '()'),
        **{name: S('', 'boolean') for name in (
            'IsServer','IsRunning','IsClient','IsStudio','IsEdit',
            'IsStandalone','IsSingleplayer','IsRunningAsync')},
    },
    'TweenService': {
        'Create': S('target: Instance, tweenInfo: TweenInfo, goals: {[string]: any}', 'Tween'),
        'GetValue': S('alpha: number, easingStyle: EnumEasingStyle, easingDirection: EnumEasingDirection', 'number'),
        'SmoothDamp': S('current: number, target: number, velocity: number, smoothTime: number, maxSpeed: number?, deltaTime: number', '(number, number)',
                        'Returns the smoothed value and updated velocity.'),
    },
    'Tween': {
        'Play': S('', '()'), 'Pause': S('', '()'), 'Cancel': S('', '()'),
    },
    'HttpService': {
        'GetAsync': S('url: string', 'string', 'Requires HTTP script permission.'),
        'PostAsync': S('url: string, body: string, contentType: string?', 'string'),
        'RequestAsync': S('request: KinemiumHttpRequest', 'KinemiumHttpResponse'),
        'GetImageBytes': S('url: string, headers: {[string]: string}?', 'Content'),
        'JSONDecode': S('encoded: string', 'any'),
        'JSONEncode': S('value: any', 'string'),
        'GenerateGUID': S('bracketed: boolean?', 'string'),
        'UrlDecode': S('encoded: string', 'string'),
        'UrlEncode': S('value: string', 'string'),
        'OpenURL': S('url: string', '()', 'Requires trusted editor permissions.'),
        'OpenLink': S('url: string', '()', 'Requires trusted editor permissions.'),
        # CreateWebStreamClient uses an internal native websocket userdata.
    },
    'CollectionService': {
        'AddTag': S('instance: Instance, tag: string', '()'),
        'RemoveTag': S('instance: Instance, tag: string', '()'),
        'HasTag': S('instance: Instance, tag: string', 'boolean'),
        'GetTags': S('instance: Instance', '{string}'),
        'GetTagged': S('tag: string', '{Instance}'),
        'GetAllTags': S('', '{string}'),
        'GetInstanceAddedSignal': S('tag: string', 'RBXScriptSignal'),
        'GetInstanceRemovedSignal': S('tag: string', 'RBXScriptSignal'),
    },
    'Model': {
        'MoveTo': S('position: Vector3', '()'),
        'TranslateBy': S('offset: Vector3', '()'),
        'GetPrimaryPartCFrame': S('', 'CFrame'),
        'SetPrimaryPartCFrame': S('cframe: CFrame', '()'),
        'GetPivot': S('', 'CFrame'),
        'PivotTo': S('cframe: CFrame', '()'),
        'GetBoundingBox': S('', '(CFrame, Vector3)', 'Returns bounding-box orientation and size.'),
        'GetExtentsSize': S('', 'Vector3'),
        'GetScale': S('', 'number'),
        'ScaleTo': S('scale: number', '()'),
    },
    'Part': {
        'GetPivot': S('', 'CFrame'), 'PivotTo': S('cframe: CFrame', '()'),
        'GetVelocityAtPosition': S('position: Vector3', 'Vector3'),
        'GetMass': S('', 'number'),
        'CanCollideWith': S('other: BasePart', 'boolean'),
        'ApplyImpulse': S('impulse: Vector3', '()'),
        'ApplyAngularImpulse': S('impulse: Vector3', '()'),
        'ApplyImpulseAtPosition': S('impulse: Vector3, position: Vector3', '()'),
        'GetConnectedParts': S('recursive: boolean?', '{BasePart}'),
        'IsGrounded': S('', 'boolean'),
        # CSG methods depend on runtime native mesh implementations.
    },
    'Humanoid': {
        'TakeDamage': S('damage: number', '()'),
        'Move': S('direction: Vector3', 'boolean'),
        'Jump': S('', 'boolean'),
        'WalkTo': S('position: Vector3', 'boolean'),
        'MoveTo': S('position: Vector3', 'boolean'),
        'ChangeState': S('state: EnumHumanoidStateType | string', '()'),
        'GetState': S('', 'string?'),
        'GetStateEnabled': S('state: EnumHumanoidStateType | string', 'boolean'),
        'SetStateEnabled': S('state: EnumHumanoidStateType | string, enabled: boolean', '()'),
    },
    'Workspace': {
        'Raycast': S('origin: Vector3, direction: Vector3, params: RaycastParams?', 'RaycastResult?'),
        'GetPartBoundsInBox': S('cframe: CFrame, size: Vector3, params: OverlapParams?', '{BasePart}'),
        'GetPartBoundsInRadius': S('center: Vector3, radius: number, params: OverlapParams?', '{BasePart}'),
        'GetPartsInPart': S('part: BasePart, params: OverlapParams?', '{BasePart}'),
        'GetNumAwakeParts': S('', 'number'),
        'GetRealPhysicsFPS': S('', 'number'),
        'Disable3D': S('', 'boolean'),
        'Enable3D': S('', 'boolean'),
    },
    'Workspace2D': {
        'Raycast': S('origin: Vector2, direction: Vector2', 'KinemiumRaycast2DResult?'),
    },
    'ChangeHistoryService': {
        'SetWaypoint': S('name: string', '()'),
        'Undo': S('', '()'), 'Redo': S('', '()'), 'ResetWaypoints': S('', '()'),
        'GetCanUndo': S('', '(boolean, string?)'),
        'GetCanRedo': S('', '(boolean, string?)'),
        'SetEnabled': S('enabled: boolean', '()'),
        'TryBeginRecording': S('name: string, displayName: string?', 'string?'),
        'FinishRecording': S('recordingId: string, operation: any', '()'),
        'IsRecordingInProgress': S('recordingId: string?', 'boolean'),
    },
    'MessagingService': {
        'Publish': S('topic: string, payload: any', '()'),
        'PublishAsync': S('topic: string, payload: any', '()'),
        'Subscribe': S('topic: string, callback: ((message: {Data: any, Sent: number, topic: string}) -> ())?', 'RBXScriptSignal | RBXScriptConnection'),
        'SubscribeAsync': S('topic: string, callback: (message: {Data: any, Sent: number, topic: string}) -> ()', 'RBXScriptConnection'),
        'Unsubscribe': S('topic: string, connection: RBXScriptConnection?', '()'),
        'UnsubscribeAll': S('topic: string?', '()'),
        'GetTopics': S('', '{string}'),
        'GetSubscribers': S('topic: string', '{number}'),
    },
    'DataStoreService': {
        'GetDataStore': S('name: string, scope: string?', 'DataStore'),
        'CreateDataStore': S('name: string, scope: string?', 'DataStore'),
        'GetGlobalDataStore': S('', 'DataStore'),
        'CreateGlobalDataStore': S('', 'DataStore'),
        'GetOrderedDataStore': S('name: string, scope: string?', 'DataStore'),
        'CreateOrderedDataStore': S('name: string, scope: string?', 'DataStore'),
        'GetRequestBudgetForRequestType': S('requestType: any?', 'number'),
        'RemoveDataStore': S('name: string, scope: string?', '()'),
    },
    'TextChatService': {
        'CanUserChatAsync': S('userId: number', 'boolean'),
        'CanUsersChatAsync': S('senderUserId: number, recipientUserId: number', 'boolean'),
        # Other TextChatService methods currently unimplemented and throw.
    },
}

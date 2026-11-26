#ifndef KINEMIUM_RUNTIME_SYMBOLS_H
#define KINEMIUM_RUNTIME_SYMBOLS_H

#define KINEMIUM_RUNTIME_SYMBOLS(X) \
    X(uint32_t, GetABIVersion, (void)) \
    X(Kinemium_Context *, Create, (void)) \
    X(void, Destroy, (Kinemium_Context *context)) \
    X(void, Update, (Kinemium_Context *context, float delta_seconds)) \
    X(void, Render, (Kinemium_Context *context, float delta_seconds)) \
    X(void *, GetService, (Kinemium_Context *context, const char *name)) \
    X(void *, GetEnvironment, (Kinemium_Context *context)) \
    X(void *, GetVM, (Kinemium_Context *context)) \
    X(void *, CreateInstance, (Kinemium_Context *context, const char *class_name)) \
    X(void, SetParent, (void *instance, void *parent)) \
    X(void, SetName, (void *instance, const char *name)) \
    X(bool, IsA, (void *instance, const char *class_name)) \
    X(void *, GetParent, (void *instance)) \
    X(void *, FindChild, (void *instance, const char *name)) \
    X(uint64_t, GetChildCount, (void *instance)) \
    X(void *, GetChildAt, (void *instance, uint64_t index)) \
    X(uint64_t, GetNameLength, (void *instance)) \
    X(uint64_t, CopyName, (void *instance, char *buffer, uint64_t capacity)) \
    X(bool, RunLuau, (Kinemium_Context *context, const char *source)) \
    X(uint64_t, GetLastErrorLength, (Kinemium_Context *context)) \
    X(uint64_t, CopyLastError, (Kinemium_Context *context, char *buffer, uint64_t capacity)) \
    X(bool, SetGlobalNumber, (Kinemium_Context *context, const char *name, double value)) \
    X(bool, GetGlobalNumber, (Kinemium_Context *context, const char *name, double *output)) \
    X(bool, SetGlobalString, (Kinemium_Context *context, const char *name, const char *value)) \
    X(int64_t, CopyGlobalString, (Kinemium_Context *context, const char *name, char *buffer, uint64_t capacity)) \
    X(Kinemium_Handle, HandleService, (Kinemium_Context *context, const char *name)) \
    X(Kinemium_Handle, HandleCreateInstance, (Kinemium_Context *context, const char *class_name)) \
    X(bool, HandleIsValid, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(bool, HandleSetName, (Kinemium_Context *context, Kinemium_Handle handle, const char *name)) \
    X(bool, HandleSetParent, (Kinemium_Context *context, Kinemium_Handle handle, Kinemium_Handle parent)) \
    X(Kinemium_Handle, HandleGetParent, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(Kinemium_Handle, HandleFindChild, (Kinemium_Context *context, Kinemium_Handle handle, const char *name)) \
    X(bool, HandleRelease, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(uint64_t, HandleGetChildCount, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(Kinemium_Handle, HandleGetChildAt, (Kinemium_Context *context, Kinemium_Handle handle, uint64_t index)) \
    X(bool, HandleIsA, (Kinemium_Context *context, Kinemium_Handle handle, const char *class_name)) \
    X(int64_t, HandleCopyName, (Kinemium_Context *context, Kinemium_Handle handle, char *buffer, uint64_t capacity)) \
    X(int64_t, HandleCopyClassName, (Kinemium_Context *context, Kinemium_Handle handle, char *buffer, uint64_t capacity)) \
    X(bool, HandleGetBooleanProperty, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, bool *output)) \
    X(bool, HandleSetBooleanProperty, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, bool value)) \
    X(bool, HandleGetNumberProperty, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, double *output)) \
    X(int64_t, HandleCopyStringProperty, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, char *buffer, uint64_t capacity)) \
    X(bool, HandleSetStringProperty, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, const char *value)) \
    X(uint64_t, HandleGetPropertyCount, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(int64_t, HandleCopyPropertyName, (Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, HandleHasProperty, (Kinemium_Context *context, Kinemium_Handle handle, const char *name)) \
    X(bool, HandleGetDynamicNumber, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, double *output)) \
    X(int64_t, HandleGetDynamicString, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, char *buffer, uint64_t capacity)) \
    X(int32_t, HandleGetPropertyType, (Kinemium_Context *context, Kinemium_Handle handle, const char *property)) \
    X(bool, HandleGetDynamicBoolean, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, bool *output)) \
    X(bool, HandleSetDynamicBoolean, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, bool value)) \
    X(bool, HandleSetDynamicNumber, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, double value)) \
    X(bool, HandleSetDynamicString, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, const char *value)) \
    X(bool, HandleGetDynamicVector3, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Vector3 *output)) \
    X(bool, HandleSetDynamicVector3, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Vector3 value)) \
    X(bool, HandleGetDynamicInstance, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Handle *output)) \
    X(bool, HandleSetDynamicInstance, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Handle value)) \
    X(bool, HandleSetDynamicNil, (Kinemium_Context *context, Kinemium_Handle handle, const char *property)) \
    X(bool, SetGlobalBoolean, (Kinemium_Context *context, const char *name, bool value)) \
    X(bool, GetGlobalBoolean, (Kinemium_Context *context, const char *name, bool *output)) \
    X(bool, SetGlobalVector3, (Kinemium_Context *context, const char *name, Kinemium_Vector3 value)) \
    X(bool, GetGlobalVector3, (Kinemium_Context *context, const char *name, Kinemium_Vector3 *output)) \
    X(bool, SetGlobalInstance, (Kinemium_Context *context, const char *name, Kinemium_Handle handle)) \
    X(bool, GetGlobalInstance, (Kinemium_Context *context, const char *name, Kinemium_Handle *output)) \
    X(Kinemium_Context *, CreateWithMode, (int32_t mode)) \
    X(int32_t, GetMode, (Kinemium_Context *context)) \
    X(bool, SetMode, (Kinemium_Context *context, int32_t mode)) \
    X(bool, Tick, (Kinemium_Context *context, float delta_seconds)) \
    X(uint64_t, GetClassCount, (Kinemium_Context *context)) \
    X(int64_t, CopyClassName, (Kinemium_Context *context, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, ClassExists, (Kinemium_Context *context, const char *name)) \
    X(bool, ClassIsCreatable, (Kinemium_Context *context, const char *name)) \
    X(uint64_t, ClassGetPropertyCount, (Kinemium_Context *context, const char *name)) \
    X(int64_t, ClassCopyPropertyName, (Kinemium_Context *context, const char *name, uint64_t index, char *buffer, uint64_t capacity)) \
    X(int64_t, HandleCopyFullName, (Kinemium_Context *context, Kinemium_Handle handle, char *buffer, uint64_t capacity)) \
    X(bool, HandleIsDescendantOf, (Kinemium_Context *context, Kinemium_Handle handle, Kinemium_Handle ancestor)) \
    X(Kinemium_Handle, HandleClone, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(bool, HandleDestroy, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(uint64_t, HandleGetDescendantCount, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(bool, PhysicsSetGravity, (Kinemium_Context *context, double gravity)) \
    X(bool, PhysicsGetGravity, (Kinemium_Context *context, double *output)) \
    X(bool, HandleApplyImpulse, (Kinemium_Context *context, Kinemium_Handle handle, Kinemium_Vector3 impulse)) \
    X(bool, HandleApplyAngularImpulse, (Kinemium_Context *context, Kinemium_Handle handle, Kinemium_Vector3 impulse)) \
    X(bool, Raycast, (Kinemium_Context *context, Kinemium_Vector3 origin, Kinemium_Vector3 direction, Kinemium_RaycastHit *output)) \
    X(bool, NetworkStartServer, (Kinemium_Context *context, const char *host, uint16_t port)) \
    X(bool, NetworkConnect, (Kinemium_Context *context, const char *host, uint16_t port)) \
    X(bool, NetworkStop, (Kinemium_Context *context)) \
    X(bool, NetworkSendStringEvent, (Kinemium_Context *context, const char *name, const char *payload, bool reliable)) \
    X(bool, NetworkSetSendRate, (Kinemium_Context *context, uint32_t bytes_per_second)) \
    X(bool, NetworkGetStats, (Kinemium_Context *context, Kinemium_NetworkStats *output)) \
    X(Kinemium_Context *, CreateHeadlessRenderer, (int32_t width, int32_t height, int32_t mode)) \
    X(bool, RenderFrame, (Kinemium_Context *context, float delta_seconds)) \
    X(bool, ResizeRenderer, (Kinemium_Context *context, int32_t width, int32_t height)) \
    X(bool, GetRendererSize, (Kinemium_Context *context, int32_t *width, int32_t *height)) \
    X(void *, GetNativeRenderer, (Kinemium_Context *context)) \
    X(bool, Invoke, (Kinemium_Context *context, Kinemium_Handle handle, const char *method, const Kinemium_Value *args, uint64_t arg_count, Kinemium_Value *output, char *text_buffer, uint64_t text_capacity)) \
    X(bool, RegisterNativeFunction, (Kinemium_Context *context, const char *name, Kinemium_NativeCallback callback, void *user_data)) \
    X(bool, UnregisterNativeFunction, (Kinemium_Context *context, const char *name)) \
    X(Kinemium_Context *, CreateForSDLWindow, (void *sdl_window, int32_t width, int32_t height, int32_t mode)) \
    X(bool, ProcessSDLEvent, (Kinemium_Context *context, const void *sdl_event)) \
    X(bool, HandleGetColor3, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Color3 *output)) \
    X(bool, HandleSetColor3, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Color3 value)) \
    X(bool, HandleGetCFrame, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_CFrame *output)) \
    X(bool, HandleSetCFrame, (Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_CFrame value)) \
    X(uint32_t, GetABIMajor, (void)) \
    X(uint32_t, GetABIMinor, (void)) \
    X(bool, ContextIsBorrowed, (Kinemium_Context *context)) \
    X(Kinemium_PluginHandle, ContextGetPlugin, (Kinemium_Context *context)) \
    X(uint64_t, ContextGetCapabilities, (Kinemium_Context *context)) \
    X(bool, PluginLoad, (Kinemium_Context *context, const char *path, Kinemium_PluginHandle *out_plugin)) \
    X(bool, PluginUnload, (Kinemium_Context *context, Kinemium_PluginHandle plugin)) \
    X(bool, PluginReload, (Kinemium_Context *context, Kinemium_PluginHandle plugin)) \
    X(uint64_t, PluginGetCount, (Kinemium_Context *context)) \
    X(bool, PluginGetInfo, (Kinemium_Context *context, Kinemium_PluginHandle plugin, Kinemium_PluginInfo *output)) \
    X(bool, RegisterClass, (Kinemium_Context *context, const Kinemium_ClassDesc *desc)) \
    X(bool, UnregisterClass, (Kinemium_Context *context, const char *name)) \
    X(bool, RegisterService, (Kinemium_Context *context, const Kinemium_ServiceDesc *desc)) \
    X(void *, HandleGetNativeData, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(Kinemium_Connection, ConnectSignal, (Kinemium_Context *context, Kinemium_Handle instance, const char *name, Kinemium_SignalCallback callback, void *user_data, bool once)) \
    X(bool, DisconnectSignal, (Kinemium_Context *context, Kinemium_Connection connection)) \
    X(bool, SignalConnected, (Kinemium_Context *context, Kinemium_Connection connection)) \
    X(bool, FireSignal, (Kinemium_Context *context, Kinemium_Handle instance, const char *name, const Kinemium_Value *arguments, uint32_t argument_count)) \
    X(bool, RegisterDatatype, (Kinemium_Context *context, const Kinemium_DatatypeDesc *desc)) \
    X(bool, UnregisterDatatype, (Kinemium_Context *context, const char *name)) \
    X(Kinemium_Callback, RetainLuauCallback, (Kinemium_Context *context, int32_t vm_index)) \
    X(Kinemium_Callback, RetainGlobalFunction, (Kinemium_Context *context, const char *name)) \
    X(bool, ReleaseLuauCallback, (Kinemium_Context *context, Kinemium_Callback callback)) \
    X(bool, CallLuauCallback, (Kinemium_Context *context, Kinemium_Callback callback, const Kinemium_Value *args, uint32_t arg_count, Kinemium_Value *result, char *text_buffer, uint64_t text_capacity)) \
    X(uint64_t, GetServiceCount, (Kinemium_Context *context)) \
    X(int64_t, CopyServiceName, (Kinemium_Context *context, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, ServiceExists, (Kinemium_Context *context, const char *name)) \
    X(bool, Log, (Kinemium_Context *context, int32_t level, const char *message)) \
    X(int64_t, CopyEngineVersion, (char *buffer, uint64_t capacity)) \
    X(bool, RegisterLibraryFunction, (Kinemium_Context *context, const char *library, const char *name, Kinemium_NativeCallback callback, void *user_data)) \
    X(bool, UnregisterLibraryFunction, (Kinemium_Context *context, const char *library, const char *name)) \
    X(uint64_t, HandleGetMethodCount, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(int64_t, HandleCopyMethodName, (Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, HandleHasMethod, (Kinemium_Context *context, Kinemium_Handle handle, const char *name)) \
    X(uint64_t, HandleGetExportCount, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(int64_t, HandleCopyExportName, (Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, HandleHasExport, (Kinemium_Context *context, Kinemium_Handle handle, const char *name)) \
    X(bool, LuauCallbackIsValid, (Kinemium_Context *context, Kinemium_Callback callback)) \
    X(bool, EvaluateLuau, (Kinemium_Context *context, const char *source, Kinemium_Value *output, char *text_buffer, uint64_t text_capacity)) \
    X(Kinemium_Connection, ConnectLuauSignal, (Kinemium_Context *context, Kinemium_Handle instance, const char *name, Kinemium_Callback callback, bool once)) \
    X(bool, InvokeExport, (Kinemium_Context *context, Kinemium_Handle handle, const char *method, const Kinemium_Value *args, uint64_t arg_count, Kinemium_Value *output, char *text_buffer, uint64_t text_capacity)) \
    X(uint64_t, HandleGetAttributeCount, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(int64_t, HandleCopyAttributeName, (Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, HandleHasAttribute, (Kinemium_Context *context, Kinemium_Handle handle, const char *name)) \
    X(bool, HandleGetAttribute, (Kinemium_Context *context, Kinemium_Handle handle, const char *name, Kinemium_Value *output, char *text_buffer, uint64_t text_capacity)) \
    X(bool, HandleSetAttribute, (Kinemium_Context *context, Kinemium_Handle handle, const char *name, const Kinemium_Value *value)) \
    X(bool, HandleRemoveAttribute, (Kinemium_Context *context, Kinemium_Handle handle, const char *name)) \
    X(uint64_t, HandleGetTagCount, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(int64_t, HandleCopyTagName, (Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, HandleHasTag, (Kinemium_Context *context, Kinemium_Handle handle, const char *tag)) \
    X(bool, HandleAddTag, (Kinemium_Context *context, Kinemium_Handle handle, const char *tag)) \
    X(bool, HandleRemoveTag, (Kinemium_Context *context, Kinemium_Handle handle, const char *tag)) \
    X(uint64_t, HandleGetMetadataRevision, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(int64_t, ClassCopyParentName, (Kinemium_Context *context, const char *class_name, char *buffer, uint64_t capacity)) \
    X(bool, ClassIsA, (Kinemium_Context *context, const char *class_name, const char *ancestor_name)) \
    X(uint64_t, ClassGetMethodCount, (Kinemium_Context *context, const char *class_name)) \
    X(int64_t, ClassCopyMethodName, (Kinemium_Context *context, const char *class_name, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, ClassHasMethod, (Kinemium_Context *context, const char *class_name, const char *method)) \
    X(uint64_t, ClassGetEventCount, (Kinemium_Context *context, const char *class_name)) \
    X(int64_t, ClassCopyEventName, (Kinemium_Context *context, const char *class_name, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, ClassHasEvent, (Kinemium_Context *context, const char *class_name, const char *event)) \
    X(uint64_t, HandleGetEventCount, (Kinemium_Context *context, Kinemium_Handle handle)) \
    X(int64_t, HandleCopyEventName, (Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity)) \
    X(bool, HandleHasEvent, (Kinemium_Context *context, Kinemium_Handle handle, const char *event)) \
    X(Kinemium_Handle, HandleFindDescendant, (Kinemium_Context *context, Kinemium_Handle ancestor, const char *name)) \
    X(Kinemium_Handle, HandleFindDescendantOfClass, (Kinemium_Context *context, Kinemium_Handle ancestor, const char *class_name)) \
    X(Kinemium_Handle, HandleGetDescendantAt, (Kinemium_Context *context, Kinemium_Handle ancestor, uint64_t index)) \
    X(uint64_t, HandleCountTaggedDescendants, (Kinemium_Context *context, Kinemium_Handle ancestor, const char *tag)) \
    X(Kinemium_Handle, HandleFindTaggedDescendant, (Kinemium_Context *context, Kinemium_Handle ancestor, const char *tag)) \
    X(Kinemium_Handle, ServiceGetHandleAt, (Kinemium_Context *context, uint64_t index)) \
    X(int64_t, ServiceCopyClassName, (Kinemium_Context *context, const char *name, char *buffer, uint64_t capacity)) \
    X(int64_t, ServiceCopyGlobalName, (Kinemium_Context *context, const char *name, char *buffer, uint64_t capacity)) \
    X(bool, ServiceIsInitialized, (Kinemium_Context *context, const char *name)) \
    X(bool, ServiceGetProperty, (Kinemium_Context *context, const char *name, const char *property, Kinemium_Value *output, char *text_buffer, uint64_t text_capacity)) \
    X(bool, ServiceSetProperty, (Kinemium_Context *context, const char *name, const char *property, const Kinemium_Value *value)) \
    X(int32_t, NetworkGetMode, (Kinemium_Context *context)) \
    X(uint32_t, NetworkGetProtocolVersion, (void)) \
    X(bool, NetworkGetDiagnostics, (Kinemium_Context *context, Kinemium_NetworkDiagnostics *output)) \
    X(bool, NetworkGetSetting, (Kinemium_Context *context, const char *name, double *output)) \
    X(bool, NetworkSetSetting, (Kinemium_Context *context, const char *name, double value)) \
    X(uint64_t, NetworkGetPeerCount, (Kinemium_Context *context)) \
    X(Kinemium_Handle, NetworkGetPeerPlayer, (Kinemium_Context *context, uint64_t index)) \
    X(bool, NetworkGetPeerUserId, (Kinemium_Context *context, uint64_t index, uint32_t *output)) \
    X(Kinemium_Connection, NetworkConnectEvent, (Kinemium_Context *context, Kinemium_SignalCallback callback, void *user_data, bool once)) \
    X(bool, NetworkSetClientEventAllowed, (Kinemium_Context *context, const char *name, bool allowed)) \
    X(bool, NetworkSendStringEventTo, (Kinemium_Context *context, Kinemium_Handle player, const char *name, const char *payload, bool reliable)) \
    X(bool, NetworkRegisterInstance, (Kinemium_Context *context, Kinemium_Handle instance, uint32_t *entity_id)) \
    X(uint32_t, NetworkGetInstanceId, (Kinemium_Context *context, Kinemium_Handle instance)) \
    X(bool, NetworkUnregisterInstance, (Kinemium_Context *context, Kinemium_Handle instance)) \
    X(bool, NetworkSetRequireJoinToken, (Kinemium_Context *context, bool required)) \
    X(bool, NetworkSetJoinToken, (Kinemium_Context *context, const char *token)) \
    X(uint64_t, PlayersGetCount, (Kinemium_Context *context)) \
    X(Kinemium_Handle, PlayersGetAt, (Kinemium_Context *context, uint64_t index)) \
    X(Kinemium_Handle, PlayersGetLocalPlayer, (Kinemium_Context *context)) \
    X(Kinemium_Handle, PlayersFindByUserId, (Kinemium_Context *context, uint32_t user_id)) \
    X(Kinemium_Handle, PlayersFindByCharacter, (Kinemium_Context *context, Kinemium_Handle character)) \
    X(bool, PlayerGetUserId, (Kinemium_Context *context, Kinemium_Handle player, uint32_t *output)) \
    X(Kinemium_Handle, PlayerGetCharacter, (Kinemium_Context *context, Kinemium_Handle player)) \
    X(bool, PlayerGetPing, (Kinemium_Context *context, Kinemium_Handle player, double *output)) \
    X(bool, PlayerGetWalkSpeed, (Kinemium_Context *context, Kinemium_Handle player, double *output)) \
    X(bool, PlayerSetWalkSpeed, (Kinemium_Context *context, Kinemium_Handle player, double value)) \
    X(bool, PlayerGetJumpPower, (Kinemium_Context *context, Kinemium_Handle player, double *output)) \
    X(bool, PlayerSetJumpPower, (Kinemium_Context *context, Kinemium_Handle player, double value)) \
    X(Kinemium_Handle, PlayerLoadCharacter, (Kinemium_Context *context, Kinemium_Handle player)) \
    X(bool, PhysicsGetLinearVelocity, (Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 *output)) \
    X(bool, PhysicsSetLinearVelocity, (Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 velocity)) \
    X(bool, PhysicsGetAngularVelocity, (Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 *output)) \
    X(bool, PhysicsSetAngularVelocity, (Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 velocity)) \
    X(bool, PhysicsGetPartMass, (Kinemium_Context *context, Kinemium_Handle part, double *output)) \
    X(bool, PhysicsGetVelocityAtPosition, (Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 world_position, Kinemium_Vector3 *output)) \
    X(bool, PhysicsApplyImpulseAtPosition, (Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 impulse, Kinemium_Vector3 world_position)) \
    X(bool, GPUComputeOpen, (Kinemium_Context *context)) \
    X(bool, GPUComputeClose, (Kinemium_Context *context)) \
    X(bool, GPUComputeGetCapabilities, (Kinemium_Context *context, Kinemium_GPUComputeCapabilities *output)) \
    X(bool, GPUComputeCreateBuffer, (Kinemium_Context *context, uint64_t bytes, uint32_t *buffer_id)) \
    X(bool, GPUComputeDestroyBuffer, (Kinemium_Context *context, uint32_t buffer_id)) \
    X(bool, GPUComputeWriteBuffer, (Kinemium_Context *context, uint32_t buffer_id, const void *data, uint64_t bytes, uint64_t offset)) \
    X(bool, GPUComputeReadBuffer, (Kinemium_Context *context, uint32_t buffer_id, uint64_t offset, uint64_t bytes, void *output, uint64_t capacity)) \
    X(bool, GPUComputeCopyBuffer, (Kinemium_Context *context, uint32_t source_id, uint32_t destination_id, uint64_t bytes, uint64_t source_offset, uint64_t destination_offset)) \
    X(bool, GPUComputeFillBuffer, (Kinemium_Context *context, uint32_t buffer_id, uint32_t value, uint64_t bytes, uint64_t offset)) \
    X(bool, GPUComputeCreatePipeline, (Kinemium_Context *context, const char *glsl_source, uint32_t binding_count, const uint32_t *binding_kinds, uint32_t *pipeline_id)) \
    X(bool, GPUComputeUsePipeline, (Kinemium_Context *context, uint32_t pipeline_id)) \
    X(bool, GPUComputeDestroyPipeline, (Kinemium_Context *context, uint32_t pipeline_id)) \
    X(bool, GPUComputeBindBuffer, (Kinemium_Context *context, uint32_t binding, uint32_t buffer_id)) \
    X(bool, GPUComputeUnbind, (Kinemium_Context *context, uint32_t binding)) \
    X(bool, GPUComputeSetPushConstants, (Kinemium_Context *context, const void *data, uint64_t bytes)) \
    X(bool, GPUComputeDispatch, (Kinemium_Context *context, uint32_t x, uint32_t y, uint32_t z)) \
    X(bool, GPUComputePoll, (Kinemium_Context *context, bool *completed)) \
    X(bool, GPUComputeBeginCommands, (Kinemium_Context *context)) \
    X(bool, GPUComputeSubmitCommands, (Kinemium_Context *context)) \
    X(bool, GPUComputeCancelCommands, (Kinemium_Context *context)) \
    X(bool, GPUComputeBarrier, (Kinemium_Context *context)) \
    X(bool, GPUComputeBeginTask, (Kinemium_Context *context)) \
    X(bool, GPUComputeSubmitTask, (Kinemium_Context *context, uint32_t x, uint32_t y, uint32_t z, uint32_t *task_id)) \
    X(bool, GPUComputeSubmitTaskBatch, (Kinemium_Context *context, uint32_t *task_id)) \
    X(bool, GPUComputePollTask, (Kinemium_Context *context, uint32_t task_id, bool *completed)) \
    X(bool, GPUComputeGetTaskInfo, (Kinemium_Context *context, uint32_t task_id, Kinemium_GPUComputeTaskInfo *output)) \
    X(uint32_t, GPUComputePendingTaskCount, (Kinemium_Context *context)) \
    X(bool, GPUComputeCreateTexture, (Kinemium_Context *context, const Kinemium_GPUComputeTextureDesc *desc, const void *pixels, uint64_t pixel_bytes, uint32_t *texture_id)) \
    X(bool, GPUComputeGetTextureInfo, (Kinemium_Context *context, uint32_t texture_id, Kinemium_GPUComputeTextureInfo *output)) \
    X(bool, GPUComputeBindTexture, (Kinemium_Context *context, uint32_t binding, uint32_t texture_id)) \
    X(bool, GPUComputeDestroyTexture, (Kinemium_Context *context, uint32_t texture_id)) \
    X(bool, GPUComputeDispatchMaterialTexture, (Kinemium_Context *context, Kinemium_Handle material_variant, const char *sampler_name, const char *glsl_source, uint32_t width, uint32_t height)) \
    X(bool, GPUComputeGetRenderStats, (Kinemium_GPUComputeRenderStats *output))

#define KINEMIUM_RUNTIME_SYMBOL_COUNT 248u

#endif

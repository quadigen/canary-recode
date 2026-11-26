#ifndef KINEMIUM_H
#define KINEMIUM_H
#include <stdint.h>
#include <stdbool.h>
#define KINEMIUM_ABI_MAJOR 2u
#define KINEMIUM_ABI_MINOR 0u
#ifdef __cplusplus
extern "C" {
#endif
#if defined(_WIN32)
#  if defined(KINEMIUM_BUILD)
#    define KINEMIUM_API __declspec(dllexport)
#  else
#    define KINEMIUM_API __declspec(dllimport)
#  endif
#else
#  define KINEMIUM_API __attribute__((visibility("default")))
#endif
typedef struct Kinemium_Context Kinemium_Context;
KINEMIUM_API uint32_t Kinemium_GetABIVersion(void);
KINEMIUM_API Kinemium_Context *Kinemium_Create(void);
KINEMIUM_API void Kinemium_Destroy(Kinemium_Context *context);
KINEMIUM_API void Kinemium_Update(Kinemium_Context *context, float delta_seconds);
KINEMIUM_API void Kinemium_Render(Kinemium_Context *context, float delta_seconds);
KINEMIUM_API void *Kinemium_GetService(Kinemium_Context *context, const char *name);
KINEMIUM_API void *Kinemium_GetEnvironment(Kinemium_Context *context);
KINEMIUM_API void *Kinemium_GetVM(Kinemium_Context *context);
KINEMIUM_API void *Kinemium_CreateInstance(Kinemium_Context *context, const char *class_name);
KINEMIUM_API void Kinemium_SetParent(void *instance, void *parent);
KINEMIUM_API void Kinemium_SetName(void *instance, const char *name);
KINEMIUM_API bool Kinemium_IsA(void *instance, const char *class_name);
KINEMIUM_API void *Kinemium_GetParent(void *instance);
KINEMIUM_API void *Kinemium_FindChild(void *instance, const char *name);
KINEMIUM_API uint64_t Kinemium_GetChildCount(void *instance);
KINEMIUM_API void *Kinemium_GetChildAt(void *instance, uint64_t index);
KINEMIUM_API uint64_t Kinemium_GetNameLength(void *instance);
KINEMIUM_API uint64_t Kinemium_CopyName(void *instance, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_RunLuau(Kinemium_Context *context, const char *source);
KINEMIUM_API uint64_t Kinemium_GetLastErrorLength(Kinemium_Context *context);
KINEMIUM_API uint64_t Kinemium_CopyLastError(Kinemium_Context *context, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_SetGlobalNumber(Kinemium_Context *context, const char *name, double value);
KINEMIUM_API bool Kinemium_GetGlobalNumber(Kinemium_Context *context, const char *name, double *output);
KINEMIUM_API bool Kinemium_SetGlobalString(Kinemium_Context *context, const char *name, const char *value);
KINEMIUM_API int64_t Kinemium_CopyGlobalString(Kinemium_Context *context, const char *name, char *buffer, uint64_t capacity);
typedef uint64_t Kinemium_Handle;
KINEMIUM_API Kinemium_Handle Kinemium_HandleService(Kinemium_Context *context, const char *name);
KINEMIUM_API Kinemium_Handle Kinemium_HandleCreateInstance(Kinemium_Context *context, const char *class_name);
KINEMIUM_API bool Kinemium_HandleIsValid(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API bool Kinemium_HandleSetName(Kinemium_Context *context, Kinemium_Handle handle, const char *name);
KINEMIUM_API bool Kinemium_HandleSetParent(Kinemium_Context *context, Kinemium_Handle handle, Kinemium_Handle parent);
KINEMIUM_API Kinemium_Handle Kinemium_HandleGetParent(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API Kinemium_Handle Kinemium_HandleFindChild(Kinemium_Context *context, Kinemium_Handle handle, const char *name);
KINEMIUM_API bool Kinemium_HandleRelease(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API uint64_t Kinemium_HandleGetChildCount(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API Kinemium_Handle Kinemium_HandleGetChildAt(Kinemium_Context *context, Kinemium_Handle handle, uint64_t index);
KINEMIUM_API bool Kinemium_HandleIsA(Kinemium_Context *context, Kinemium_Handle handle, const char *class_name);
KINEMIUM_API int64_t Kinemium_HandleCopyName(Kinemium_Context *context, Kinemium_Handle handle, char *buffer, uint64_t capacity);
KINEMIUM_API int64_t Kinemium_HandleCopyClassName(Kinemium_Context *context, Kinemium_Handle handle, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleGetBooleanProperty(Kinemium_Context *context, Kinemium_Handle handle, const char *property, bool *output);
KINEMIUM_API bool Kinemium_HandleSetBooleanProperty(Kinemium_Context *context, Kinemium_Handle handle, const char *property, bool value);
KINEMIUM_API bool Kinemium_HandleGetNumberProperty(Kinemium_Context *context, Kinemium_Handle handle, const char *property, double *output);
KINEMIUM_API int64_t Kinemium_HandleCopyStringProperty(Kinemium_Context *context, Kinemium_Handle handle, const char *property, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleSetStringProperty(Kinemium_Context *context, Kinemium_Handle handle, const char *property, const char *value);
KINEMIUM_API uint64_t Kinemium_HandleGetPropertyCount(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API int64_t Kinemium_HandleCopyPropertyName(Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleHasProperty(Kinemium_Context *context, Kinemium_Handle handle, const char *name);
KINEMIUM_API bool Kinemium_HandleGetDynamicNumber(Kinemium_Context *context, Kinemium_Handle handle, const char *property, double *output);
KINEMIUM_API int64_t Kinemium_HandleGetDynamicString(Kinemium_Context *context, Kinemium_Handle handle, const char *property, char *buffer, uint64_t capacity);
typedef struct Kinemium_Vector3 {
    double x;
    double y;
    double z;
} Kinemium_Vector3;
typedef enum Kinemium_PropertyType {
    KINEMIUM_PROPERTY_INVALID = -1,
    KINEMIUM_PROPERTY_NIL = 0,
    KINEMIUM_PROPERTY_BOOLEAN = 1,
    KINEMIUM_PROPERTY_NUMBER = 2,
    KINEMIUM_PROPERTY_STRING = 3,
    KINEMIUM_PROPERTY_VECTOR3 = 4,
    KINEMIUM_PROPERTY_INSTANCE = 5,
    KINEMIUM_PROPERTY_OTHER = 6
} Kinemium_PropertyType;
KINEMIUM_API int32_t Kinemium_HandleGetPropertyType(Kinemium_Context *context, Kinemium_Handle handle, const char *property);
KINEMIUM_API bool Kinemium_HandleGetDynamicBoolean(Kinemium_Context *context, Kinemium_Handle handle, const char *property, bool *output);
KINEMIUM_API bool Kinemium_HandleSetDynamicBoolean(Kinemium_Context *context, Kinemium_Handle handle, const char *property, bool value);
KINEMIUM_API bool Kinemium_HandleSetDynamicNumber(Kinemium_Context *context, Kinemium_Handle handle, const char *property, double value);
KINEMIUM_API bool Kinemium_HandleSetDynamicString(Kinemium_Context *context, Kinemium_Handle handle, const char *property, const char *value);
KINEMIUM_API bool Kinemium_HandleGetDynamicVector3(Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Vector3 *output);
KINEMIUM_API bool Kinemium_HandleSetDynamicVector3(Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Vector3 value);
KINEMIUM_API bool Kinemium_HandleGetDynamicInstance(Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Handle *output);
KINEMIUM_API bool Kinemium_HandleSetDynamicInstance(Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Handle value);
KINEMIUM_API bool Kinemium_HandleSetDynamicNil(Kinemium_Context *context, Kinemium_Handle handle, const char *property);
KINEMIUM_API bool Kinemium_SetGlobalBoolean(Kinemium_Context *context, const char *name, bool value);
KINEMIUM_API bool Kinemium_GetGlobalBoolean(Kinemium_Context *context, const char *name, bool *output);
KINEMIUM_API bool Kinemium_SetGlobalVector3(Kinemium_Context *context, const char *name, Kinemium_Vector3 value);
KINEMIUM_API bool Kinemium_GetGlobalVector3(Kinemium_Context *context, const char *name, Kinemium_Vector3 *output);
KINEMIUM_API bool Kinemium_SetGlobalInstance(Kinemium_Context *context, const char *name, Kinemium_Handle handle);
KINEMIUM_API bool Kinemium_GetGlobalInstance(Kinemium_Context *context, const char *name, Kinemium_Handle *output);
typedef enum Kinemium_Mode {
    KINEMIUM_MODE_EDITOR = 0,
    KINEMIUM_MODE_CLIENT = 1,
    KINEMIUM_MODE_SERVER = 2,
    KINEMIUM_MODE_STANDALONE = 3,
    KINEMIUM_MODE_SINGLEPLAYER = 4
} Kinemium_Mode;
typedef struct Kinemium_RaycastHit {
    Kinemium_Handle instance;
    Kinemium_Vector3 position;
    Kinemium_Vector3 normal;
    double distance;
    int32_t material;
} Kinemium_RaycastHit;
KINEMIUM_API Kinemium_Context *Kinemium_CreateWithMode(int32_t mode);
KINEMIUM_API int32_t Kinemium_GetMode(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_SetMode(Kinemium_Context *context, int32_t mode);
KINEMIUM_API bool Kinemium_Tick(Kinemium_Context *context, float delta_seconds);
KINEMIUM_API uint64_t Kinemium_GetClassCount(Kinemium_Context *context);
KINEMIUM_API int64_t Kinemium_CopyClassName(Kinemium_Context *context, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_ClassExists(Kinemium_Context *context, const char *name);
KINEMIUM_API bool Kinemium_ClassIsCreatable(Kinemium_Context *context, const char *name);
KINEMIUM_API uint64_t Kinemium_ClassGetPropertyCount(Kinemium_Context *context, const char *name);
KINEMIUM_API int64_t Kinemium_ClassCopyPropertyName(Kinemium_Context *context, const char *name, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API int64_t Kinemium_HandleCopyFullName(Kinemium_Context *context, Kinemium_Handle handle, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleIsDescendantOf(Kinemium_Context *context, Kinemium_Handle handle, Kinemium_Handle ancestor);
KINEMIUM_API Kinemium_Handle Kinemium_HandleClone(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API bool Kinemium_HandleDestroy(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API uint64_t Kinemium_HandleGetDescendantCount(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API bool Kinemium_PhysicsSetGravity(Kinemium_Context *context, double gravity);
KINEMIUM_API bool Kinemium_PhysicsGetGravity(Kinemium_Context *context, double *output);
KINEMIUM_API bool Kinemium_HandleApplyImpulse(Kinemium_Context *context, Kinemium_Handle handle, Kinemium_Vector3 impulse);
KINEMIUM_API bool Kinemium_HandleApplyAngularImpulse(Kinemium_Context *context, Kinemium_Handle handle, Kinemium_Vector3 impulse);
KINEMIUM_API bool Kinemium_Raycast(Kinemium_Context *context, Kinemium_Vector3 origin, Kinemium_Vector3 direction, Kinemium_RaycastHit *output);
typedef struct Kinemium_NetworkStats {
    bool connected;
    bool scene_ready;
    uint32_t peers;
    uint32_t replicated_entities;
    uint64_t packets_sent;
    uint64_t packets_received;
    uint64_t bytes_sent;
    uint64_t bytes_received;
} Kinemium_NetworkStats;
KINEMIUM_API bool Kinemium_NetworkStartServer(Kinemium_Context *context, const char *host, uint16_t port);
KINEMIUM_API bool Kinemium_NetworkConnect(Kinemium_Context *context, const char *host, uint16_t port);
KINEMIUM_API bool Kinemium_NetworkStop(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_NetworkSendStringEvent(Kinemium_Context *context, const char *name, const char *payload, bool reliable);
KINEMIUM_API bool Kinemium_NetworkSetSendRate(Kinemium_Context *context, uint32_t bytes_per_second);
KINEMIUM_API bool Kinemium_NetworkGetStats(Kinemium_Context *context, Kinemium_NetworkStats *output);
KINEMIUM_API Kinemium_Context *Kinemium_CreateHeadlessRenderer(int32_t width, int32_t height, int32_t mode);
KINEMIUM_API bool Kinemium_RenderFrame(Kinemium_Context *context, float delta_seconds);
KINEMIUM_API bool Kinemium_ResizeRenderer(Kinemium_Context *context, int32_t width, int32_t height);
KINEMIUM_API bool Kinemium_GetRendererSize(Kinemium_Context *context, int32_t *width, int32_t *height);
KINEMIUM_API void *Kinemium_GetNativeRenderer(Kinemium_Context *context);
typedef enum Kinemium_ValueKind {
    KINEMIUM_VALUE_NIL = 0,
    KINEMIUM_VALUE_BOOLEAN = 1,
    KINEMIUM_VALUE_NUMBER = 2,
    KINEMIUM_VALUE_STRING = 3,
    KINEMIUM_VALUE_VECTOR3 = 4,
    KINEMIUM_VALUE_INSTANCE = 5,
    KINEMIUM_VALUE_OTHER = 6
} Kinemium_ValueKind;
typedef struct Kinemium_Value {
    Kinemium_ValueKind kind;
    double number;
    bool boolean;
    Kinemium_Vector3 vector;
    Kinemium_Handle instance;
    const char *text;
    uint64_t text_length;
} Kinemium_Value;
KINEMIUM_API bool Kinemium_Invoke(Kinemium_Context *context, Kinemium_Handle handle,
    const char *method, const Kinemium_Value *args, uint64_t arg_count,
    Kinemium_Value *output, char *text_buffer, uint64_t text_capacity);
typedef bool (*Kinemium_NativeCallback)(void *user_data, uint32_t argument_count,
    const Kinemium_Value *arguments, Kinemium_Value *output);
KINEMIUM_API bool Kinemium_RegisterNativeFunction(Kinemium_Context *context, const char *name,
    Kinemium_NativeCallback callback, void *user_data);
KINEMIUM_API bool Kinemium_UnregisterNativeFunction(Kinemium_Context *context, const char *name);
KINEMIUM_API Kinemium_Context *Kinemium_CreateForSDLWindow(void *sdl_window, int32_t width, int32_t height, int32_t mode);
KINEMIUM_API bool Kinemium_ProcessSDLEvent(Kinemium_Context *context, const void *sdl_event);
typedef struct Kinemium_Color3 {
    double r;
    double g;
    double b;
} Kinemium_Color3;
typedef struct Kinemium_CFrame {
    double x;
    double y;
    double z;
    double r00;
    double r01;
    double r02;
    double r10;
    double r11;
    double r12;
    double r20;
    double r21;
    double r22;
} Kinemium_CFrame;
KINEMIUM_API bool Kinemium_HandleGetColor3(Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Color3 *output);
KINEMIUM_API bool Kinemium_HandleSetColor3(Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_Color3 value);
KINEMIUM_API bool Kinemium_HandleGetCFrame(Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_CFrame *output);
KINEMIUM_API bool Kinemium_HandleSetCFrame(Kinemium_Context *context, Kinemium_Handle handle, const char *property, Kinemium_CFrame value);
typedef uint64_t Kinemium_PluginHandle;
typedef struct Kinemium_PluginInfo {
    Kinemium_PluginHandle handle;
    bool active;
    uint32_t abi_major;
    uint32_t abi_minor;
} Kinemium_PluginInfo;
KINEMIUM_API uint32_t Kinemium_GetABIMajor(void);
KINEMIUM_API uint32_t Kinemium_GetABIMinor(void);
KINEMIUM_API bool Kinemium_ContextIsBorrowed(Kinemium_Context *context);
KINEMIUM_API Kinemium_PluginHandle Kinemium_ContextGetPlugin(Kinemium_Context *context);
KINEMIUM_API uint64_t Kinemium_ContextGetCapabilities(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_PluginLoad(Kinemium_Context *context, const char *path, Kinemium_PluginHandle *out_plugin);
KINEMIUM_API bool Kinemium_PluginUnload(Kinemium_Context *context, Kinemium_PluginHandle plugin);
KINEMIUM_API bool Kinemium_PluginReload(Kinemium_Context *context, Kinemium_PluginHandle plugin);
KINEMIUM_API uint64_t Kinemium_PluginGetCount(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_PluginGetInfo(Kinemium_Context *context, Kinemium_PluginHandle plugin, Kinemium_PluginInfo *output);
typedef enum Kinemium_PropertyKind {
    KINEMIUM_BOOLEAN = 1,
    KINEMIUM_NUMBER = 2,
    KINEMIUM_STRING = 3,
    KINEMIUM_VECTOR3 = 4,
    KINEMIUM_COLOR3 = 5,
    KINEMIUM_CFRAME = 6,
    KINEMIUM_INTEGER = 7
} Kinemium_PropertyKind;
#define KINEMIUM_CLASS_CREATABLE 1u
#define KINEMIUM_CLASS_SERVICE 2u
#define KINEMIUM_CLASS_MAX_PROPERTIES 32u
#define KINEMIUM_CLASS_MAX_METHODS 16u
typedef struct Kinemium_ClassPropertyDesc {
    const char *name;
    Kinemium_PropertyKind kind;
    uint64_t offset;
    bool read_only;
} Kinemium_ClassPropertyDesc;
typedef bool (*Kinemium_ClassMethodFn)(Kinemium_Context *context, void *data,
    uint32_t argument_count, const Kinemium_Value *arguments, Kinemium_Value *output);
typedef struct Kinemium_ClassMethodDesc {
    const char *name;
    Kinemium_ClassMethodFn callback;
} Kinemium_ClassMethodDesc;
typedef void (*Kinemium_ClassConstructFn)(Kinemium_Context *context, void *data);
typedef void (*Kinemium_ClassStepFn)(Kinemium_Context *context, void *data, double delta_seconds);
typedef bool (*Kinemium_ClassGetFn)(Kinemium_Context *context, void *data, const char *name, Kinemium_Value *output);
typedef bool (*Kinemium_ClassSetFn)(Kinemium_Context *context, void *data, const char *name, const Kinemium_Value *input);
typedef struct Kinemium_BatchInstance {
    Kinemium_Handle instance;
    void *data;
} Kinemium_BatchInstance;
typedef void (*Kinemium_ClassBatchStepFn)(Kinemium_Context *context,
    Kinemium_BatchInstance *instances, uint32_t count, double delta_seconds);
typedef struct Kinemium_ClassDesc {
    uint32_t size;
    uint32_t flags;
    const char *name;
    const char *base;
    uint64_t data_size;
    uint32_t property_count;
    uint32_t method_count;
    Kinemium_ClassPropertyDesc properties[KINEMIUM_CLASS_MAX_PROPERTIES];
    Kinemium_ClassMethodDesc methods[KINEMIUM_CLASS_MAX_METHODS];
    Kinemium_ClassConstructFn on_construct;
    Kinemium_ClassConstructFn on_destroy;
    Kinemium_ClassStepFn on_step;
    Kinemium_ClassBatchStepFn on_batch_step;
    Kinemium_ClassGetFn on_get;
    Kinemium_ClassSetFn on_set;
} Kinemium_ClassDesc;
typedef Kinemium_ClassDesc Kinemium_ServiceDesc;
KINEMIUM_API bool Kinemium_RegisterClass(Kinemium_Context *context, const Kinemium_ClassDesc *desc);
KINEMIUM_API bool Kinemium_UnregisterClass(Kinemium_Context *context, const char *name);
KINEMIUM_API bool Kinemium_RegisterService(Kinemium_Context *context, const Kinemium_ServiceDesc *desc);
KINEMIUM_API void *Kinemium_HandleGetNativeData(Kinemium_Context *context, Kinemium_Handle handle);
typedef uint64_t Kinemium_Connection;
typedef void (*Kinemium_SignalCallback)(Kinemium_Context *context, void *user_data,
    uint32_t argument_count, const Kinemium_Value *arguments);
KINEMIUM_API Kinemium_Connection Kinemium_ConnectSignal(Kinemium_Context *context,
    Kinemium_Handle instance, const char *name, Kinemium_SignalCallback callback,
    void *user_data, bool once);
KINEMIUM_API bool Kinemium_DisconnectSignal(Kinemium_Context *context, Kinemium_Connection connection);
KINEMIUM_API bool Kinemium_SignalConnected(Kinemium_Context *context, Kinemium_Connection connection);
KINEMIUM_API bool Kinemium_FireSignal(Kinemium_Context *context, Kinemium_Handle instance,
    const char *name, const Kinemium_Value *arguments, uint32_t argument_count);
typedef bool (*Kinemium_DatatypeConstructFn)(Kinemium_Context *context, void *data,
    uint32_t count, const Kinemium_Value *arguments);
typedef int32_t (*Kinemium_DatatypeEncodeFn)(Kinemium_Context *context, void *data,
    void *buffer, uint64_t capacity, uint64_t *required_size);
typedef bool (*Kinemium_DatatypeDecodeFn)(Kinemium_Context *context, void *data,
    const void *buffer, uint64_t size);
#define KINEMIUM_DATATYPE_PERSISTABLE 1u
#define KINEMIUM_DATATYPE_REPLICATED 2u
typedef bool (*Kinemium_DatatypeBinaryFn)(Kinemium_Context *context, const void *left,
    const void *right, void *output);
typedef bool (*Kinemium_DatatypeEqualFn)(Kinemium_Context *context, const void *left,
    const void *right);
typedef const char *(*Kinemium_DatatypeStringFn)(Kinemium_Context *context, const void *value);
typedef struct Kinemium_DatatypeDesc {
    uint32_t size;
    uint32_t flags;
    const char *name;
    const char *library;
    uint64_t data_size;
    uint32_t wire_version;
    uint32_t property_count;
    uint32_t method_count;
    Kinemium_ClassPropertyDesc properties[KINEMIUM_CLASS_MAX_PROPERTIES];
    Kinemium_ClassMethodDesc methods[KINEMIUM_CLASS_MAX_METHODS];
    Kinemium_DatatypeConstructFn on_construct;
    Kinemium_ClassConstructFn on_destroy;
    Kinemium_DatatypeEncodeFn on_encode;
    Kinemium_DatatypeDecodeFn on_decode;
    Kinemium_DatatypeBinaryFn on_add;
    Kinemium_DatatypeBinaryFn on_subtract;
    Kinemium_DatatypeBinaryFn on_multiply;
    Kinemium_DatatypeBinaryFn on_divide;
    Kinemium_DatatypeBinaryFn on_negate;
    Kinemium_DatatypeEqualFn on_equal;
    Kinemium_DatatypeStringFn on_string;
} Kinemium_DatatypeDesc;
KINEMIUM_API bool Kinemium_RegisterDatatype(Kinemium_Context *context, const Kinemium_DatatypeDesc *desc);
KINEMIUM_API bool Kinemium_UnregisterDatatype(Kinemium_Context *context, const char *name);
typedef uint64_t Kinemium_Callback;
KINEMIUM_API Kinemium_Callback Kinemium_RetainLuauCallback(Kinemium_Context *context, int32_t vm_index);
KINEMIUM_API Kinemium_Callback Kinemium_RetainGlobalFunction(Kinemium_Context *context, const char *name);
KINEMIUM_API bool Kinemium_ReleaseLuauCallback(Kinemium_Context *context, Kinemium_Callback callback);
KINEMIUM_API bool Kinemium_CallLuauCallback(Kinemium_Context *context, Kinemium_Callback callback,
    const Kinemium_Value *args, uint32_t arg_count, Kinemium_Value *result,
    char *text_buffer, uint64_t text_capacity);
typedef enum Kinemium_LogLevel {
    KINEMIUM_LOG_TRACE = 0,
    KINEMIUM_LOG_DEBUG = 1,
    KINEMIUM_LOG_INFO = 2,
    KINEMIUM_LOG_WARN = 3,
    KINEMIUM_LOG_ERROR = 4
} Kinemium_LogLevel;
KINEMIUM_API uint64_t Kinemium_GetServiceCount(Kinemium_Context *context);
KINEMIUM_API int64_t Kinemium_CopyServiceName(Kinemium_Context *context, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_ServiceExists(Kinemium_Context *context, const char *name);
KINEMIUM_API bool Kinemium_Log(Kinemium_Context *context, int32_t level, const char *message);
KINEMIUM_API int64_t Kinemium_CopyEngineVersion(char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_RegisterLibraryFunction(Kinemium_Context *context, const char *library, const char *name,
    Kinemium_NativeCallback callback, void *user_data);
KINEMIUM_API bool Kinemium_UnregisterLibraryFunction(Kinemium_Context *context, const char *library, const char *name);
KINEMIUM_API uint64_t Kinemium_HandleGetMethodCount(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API int64_t Kinemium_HandleCopyMethodName(Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleHasMethod(Kinemium_Context *context, Kinemium_Handle handle, const char *name);
KINEMIUM_API uint64_t Kinemium_HandleGetExportCount(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API int64_t Kinemium_HandleCopyExportName(Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleHasExport(Kinemium_Context *context, Kinemium_Handle handle, const char *name);
KINEMIUM_API bool Kinemium_LuauCallbackIsValid(Kinemium_Context *context, Kinemium_Callback callback);
KINEMIUM_API bool Kinemium_EvaluateLuau(Kinemium_Context *context, const char *source,
    Kinemium_Value *output, char *text_buffer, uint64_t text_capacity);
KINEMIUM_API Kinemium_Connection Kinemium_ConnectLuauSignal(Kinemium_Context *context,
    Kinemium_Handle instance, const char *name, Kinemium_Callback callback, bool once);
KINEMIUM_API bool Kinemium_InvokeExport(Kinemium_Context *context, Kinemium_Handle handle,
    const char *method, const Kinemium_Value *args, uint64_t arg_count,
    Kinemium_Value *output, char *text_buffer, uint64_t text_capacity);
KINEMIUM_API uint64_t Kinemium_HandleGetAttributeCount(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API int64_t Kinemium_HandleCopyAttributeName(Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleHasAttribute(Kinemium_Context *context, Kinemium_Handle handle, const char *name);
KINEMIUM_API bool Kinemium_HandleGetAttribute(Kinemium_Context *context, Kinemium_Handle handle, const char *name, Kinemium_Value *output, char *text_buffer, uint64_t text_capacity);
KINEMIUM_API bool Kinemium_HandleSetAttribute(Kinemium_Context *context, Kinemium_Handle handle, const char *name, const Kinemium_Value *value);
KINEMIUM_API bool Kinemium_HandleRemoveAttribute(Kinemium_Context *context, Kinemium_Handle handle, const char *name);
KINEMIUM_API uint64_t Kinemium_HandleGetTagCount(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API int64_t Kinemium_HandleCopyTagName(Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleHasTag(Kinemium_Context *context, Kinemium_Handle handle, const char *tag);
KINEMIUM_API bool Kinemium_HandleAddTag(Kinemium_Context *context, Kinemium_Handle handle, const char *tag);
KINEMIUM_API bool Kinemium_HandleRemoveTag(Kinemium_Context *context, Kinemium_Handle handle, const char *tag);
KINEMIUM_API uint64_t Kinemium_HandleGetMetadataRevision(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API int64_t Kinemium_ClassCopyParentName(Kinemium_Context *context, const char *class_name, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_ClassIsA(Kinemium_Context *context, const char *class_name, const char *ancestor_name);
KINEMIUM_API uint64_t Kinemium_ClassGetMethodCount(Kinemium_Context *context, const char *class_name);
KINEMIUM_API int64_t Kinemium_ClassCopyMethodName(Kinemium_Context *context, const char *class_name, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_ClassHasMethod(Kinemium_Context *context, const char *class_name, const char *method);
KINEMIUM_API uint64_t Kinemium_ClassGetEventCount(Kinemium_Context *context, const char *class_name);
KINEMIUM_API int64_t Kinemium_ClassCopyEventName(Kinemium_Context *context, const char *class_name, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_ClassHasEvent(Kinemium_Context *context, const char *class_name, const char *event);
KINEMIUM_API uint64_t Kinemium_HandleGetEventCount(Kinemium_Context *context, Kinemium_Handle handle);
KINEMIUM_API int64_t Kinemium_HandleCopyEventName(Kinemium_Context *context, Kinemium_Handle handle, uint64_t index, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_HandleHasEvent(Kinemium_Context *context, Kinemium_Handle handle, const char *event);
KINEMIUM_API Kinemium_Handle Kinemium_HandleFindDescendant(Kinemium_Context *context, Kinemium_Handle ancestor, const char *name);
KINEMIUM_API Kinemium_Handle Kinemium_HandleFindDescendantOfClass(Kinemium_Context *context, Kinemium_Handle ancestor, const char *class_name);
KINEMIUM_API Kinemium_Handle Kinemium_HandleGetDescendantAt(Kinemium_Context *context, Kinemium_Handle ancestor, uint64_t index);
KINEMIUM_API uint64_t Kinemium_HandleCountTaggedDescendants(Kinemium_Context *context, Kinemium_Handle ancestor, const char *tag);
KINEMIUM_API Kinemium_Handle Kinemium_HandleFindTaggedDescendant(Kinemium_Context *context, Kinemium_Handle ancestor, const char *tag);


KINEMIUM_API Kinemium_Handle Kinemium_ServiceGetHandleAt(Kinemium_Context *context, uint64_t index);
KINEMIUM_API int64_t Kinemium_ServiceCopyClassName(Kinemium_Context *context, const char *name, char *buffer, uint64_t capacity);
KINEMIUM_API int64_t Kinemium_ServiceCopyGlobalName(Kinemium_Context *context, const char *name, char *buffer, uint64_t capacity);
KINEMIUM_API bool Kinemium_ServiceIsInitialized(Kinemium_Context *context, const char *name);
KINEMIUM_API bool Kinemium_ServiceGetProperty(Kinemium_Context *context, const char *name, const char *property,
    Kinemium_Value *output, char *text_buffer, uint64_t text_capacity);
KINEMIUM_API bool Kinemium_ServiceSetProperty(Kinemium_Context *context, const char *name, const char *property,
    const Kinemium_Value *value);


typedef enum Kinemium_NetworkMode {
    KINEMIUM_NETWORK_STOPPED = 0,
    KINEMIUM_NETWORK_SERVER = 1,
    KINEMIUM_NETWORK_CLIENT = 2
} Kinemium_NetworkMode;
typedef struct Kinemium_NetworkDiagnostics {
    int32_t mode;
    bool handshake_complete;
    bool scene_ready;
    bool replication_finished;
    uint32_t protocol_version;
    uint32_t handshake_status;
    uint64_t handshake_rejections;
    uint64_t malformed_packets;
    uint64_t rejected_packets;
    uint64_t version_mismatches;
    uint64_t schema_mismatches;
    uint64_t auth_failures;
    uint64_t bandwidth_drops;
    uint64_t states_applied;
    uint32_t tick;
} Kinemium_NetworkDiagnostics;
KINEMIUM_API int32_t Kinemium_NetworkGetMode(Kinemium_Context *context);
KINEMIUM_API uint32_t Kinemium_NetworkGetProtocolVersion(void);
KINEMIUM_API bool Kinemium_NetworkGetDiagnostics(Kinemium_Context *context, Kinemium_NetworkDiagnostics *output);
KINEMIUM_API bool Kinemium_NetworkGetSetting(Kinemium_Context *context, const char *name, double *output);
KINEMIUM_API bool Kinemium_NetworkSetSetting(Kinemium_Context *context, const char *name, double value);
KINEMIUM_API uint64_t Kinemium_NetworkGetPeerCount(Kinemium_Context *context);
KINEMIUM_API Kinemium_Handle Kinemium_NetworkGetPeerPlayer(Kinemium_Context *context, uint64_t index);
KINEMIUM_API bool Kinemium_NetworkGetPeerUserId(Kinemium_Context *context, uint64_t index, uint32_t *output);
KINEMIUM_API Kinemium_Connection Kinemium_NetworkConnectEvent(Kinemium_Context *context,
    Kinemium_SignalCallback callback, void *user_data, bool once);
KINEMIUM_API bool Kinemium_NetworkSetClientEventAllowed(Kinemium_Context *context, const char *name, bool allowed);
KINEMIUM_API bool Kinemium_NetworkSendStringEventTo(Kinemium_Context *context, Kinemium_Handle player,
    const char *name, const char *payload, bool reliable);
KINEMIUM_API bool Kinemium_NetworkRegisterInstance(Kinemium_Context *context, Kinemium_Handle instance, uint32_t *entity_id);
KINEMIUM_API uint32_t Kinemium_NetworkGetInstanceId(Kinemium_Context *context, Kinemium_Handle instance);
KINEMIUM_API bool Kinemium_NetworkUnregisterInstance(Kinemium_Context *context, Kinemium_Handle instance);
KINEMIUM_API bool Kinemium_NetworkSetRequireJoinToken(Kinemium_Context *context, bool required);
KINEMIUM_API bool Kinemium_NetworkSetJoinToken(Kinemium_Context *context, const char *token);


KINEMIUM_API uint64_t Kinemium_PlayersGetCount(Kinemium_Context *context);
KINEMIUM_API Kinemium_Handle Kinemium_PlayersGetAt(Kinemium_Context *context, uint64_t index);
KINEMIUM_API Kinemium_Handle Kinemium_PlayersGetLocalPlayer(Kinemium_Context *context);
KINEMIUM_API Kinemium_Handle Kinemium_PlayersFindByUserId(Kinemium_Context *context, uint32_t user_id);
KINEMIUM_API Kinemium_Handle Kinemium_PlayersFindByCharacter(Kinemium_Context *context, Kinemium_Handle character);
KINEMIUM_API bool Kinemium_PlayerGetUserId(Kinemium_Context *context, Kinemium_Handle player, uint32_t *output);
KINEMIUM_API Kinemium_Handle Kinemium_PlayerGetCharacter(Kinemium_Context *context, Kinemium_Handle player);
KINEMIUM_API bool Kinemium_PlayerGetPing(Kinemium_Context *context, Kinemium_Handle player, double *output);
KINEMIUM_API bool Kinemium_PlayerGetWalkSpeed(Kinemium_Context *context, Kinemium_Handle player, double *output);
KINEMIUM_API bool Kinemium_PlayerSetWalkSpeed(Kinemium_Context *context, Kinemium_Handle player, double value);
KINEMIUM_API bool Kinemium_PlayerGetJumpPower(Kinemium_Context *context, Kinemium_Handle player, double *output);
KINEMIUM_API bool Kinemium_PlayerSetJumpPower(Kinemium_Context *context, Kinemium_Handle player, double value);
KINEMIUM_API Kinemium_Handle Kinemium_PlayerLoadCharacter(Kinemium_Context *context, Kinemium_Handle player);


KINEMIUM_API bool Kinemium_PhysicsGetLinearVelocity(Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 *output);
KINEMIUM_API bool Kinemium_PhysicsSetLinearVelocity(Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 velocity);
KINEMIUM_API bool Kinemium_PhysicsGetAngularVelocity(Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 *output);
KINEMIUM_API bool Kinemium_PhysicsSetAngularVelocity(Kinemium_Context *context, Kinemium_Handle part, Kinemium_Vector3 velocity);
KINEMIUM_API bool Kinemium_PhysicsGetPartMass(Kinemium_Context *context, Kinemium_Handle part, double *output);
KINEMIUM_API bool Kinemium_PhysicsGetVelocityAtPosition(Kinemium_Context *context, Kinemium_Handle part,
    Kinemium_Vector3 world_position, Kinemium_Vector3 *output);
KINEMIUM_API bool Kinemium_PhysicsApplyImpulseAtPosition(Kinemium_Context *context, Kinemium_Handle part,
    Kinemium_Vector3 impulse, Kinemium_Vector3 world_position);


typedef enum Kinemium_GPUComputeBindingKind {
    KINEMIUM_GPU_BIND_STORAGE_BUFFER = 0,
    KINEMIUM_GPU_BIND_UNIFORM_BUFFER = 1,
    KINEMIUM_GPU_BIND_SAMPLED_TEXTURE = 2,
    KINEMIUM_GPU_BIND_STORAGE_TEXTURE = 3
} Kinemium_GPUComputeBindingKind;
typedef enum Kinemium_GPUComputeTextureFormat {
    KINEMIUM_GPU_TEXTURE_RGBA8 = 0,
    KINEMIUM_GPU_TEXTURE_RGBA8_SRGB = 1,
    KINEMIUM_GPU_TEXTURE_R8 = 2,
    KINEMIUM_GPU_TEXTURE_RG8 = 3,
    KINEMIUM_GPU_TEXTURE_R32F = 4,
    KINEMIUM_GPU_TEXTURE_RG32F = 5,
    KINEMIUM_GPU_TEXTURE_RGBA16F = 6,
    KINEMIUM_GPU_TEXTURE_RGBA32F = 7,
    KINEMIUM_GPU_TEXTURE_R32UI = 8
} Kinemium_GPUComputeTextureFormat;
typedef enum Kinemium_GPUComputeTextureDimension {
    KINEMIUM_GPU_TEXTURE_1D = 0,
    KINEMIUM_GPU_TEXTURE_2D = 1,
    KINEMIUM_GPU_TEXTURE_3D = 2,
    KINEMIUM_GPU_TEXTURE_2D_ARRAY = 3
} Kinemium_GPUComputeTextureDimension;
typedef struct Kinemium_GPUComputeCapabilities {
    char name[256];
    uint32_t max_buffer_size, max_uniform_size;
    uint32_t max_texture_1d, max_texture_2d, max_texture_3d, max_texture_layers;
    uint32_t max_shared_memory, max_workgroup_invocations;
    uint32_t max_workgroup_size[3], max_workgroup_count[3];
    bool float64, int64, int16, extended_storage;
    uint32_t compute_queues;
    bool timeline_semaphores;
} Kinemium_GPUComputeCapabilities;
typedef struct Kinemium_GPUComputeTaskInfo {
    uint32_t queue, dispatch_count;
    bool complete;
} Kinemium_GPUComputeTaskInfo;
typedef struct Kinemium_GPUComputeTextureDesc {
    uint32_t width, height, depth, layers;
    uint32_t format, dimension;
    bool writable, nearest, clamp, mipmaps;
} Kinemium_GPUComputeTextureDesc;
typedef struct Kinemium_GPUComputeTextureInfo {
    Kinemium_GPUComputeTextureDesc desc;
    uint32_t mip_levels;
} Kinemium_GPUComputeTextureInfo;
typedef struct Kinemium_GPUComputeRenderStats {
    uint64_t direct_texture_dispatches, direct_texture_bytes;
    uint64_t pixel_readback_bytes, pixel_upload_bytes;
} Kinemium_GPUComputeRenderStats;

KINEMIUM_API bool Kinemium_GPUComputeOpen(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_GPUComputeClose(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_GPUComputeGetCapabilities(Kinemium_Context *context, Kinemium_GPUComputeCapabilities *output);
KINEMIUM_API bool Kinemium_GPUComputeCreateBuffer(Kinemium_Context *context, uint64_t bytes, uint32_t *buffer_id);
KINEMIUM_API bool Kinemium_GPUComputeDestroyBuffer(Kinemium_Context *context, uint32_t buffer_id);
KINEMIUM_API bool Kinemium_GPUComputeWriteBuffer(Kinemium_Context *context, uint32_t buffer_id, const void *data, uint64_t bytes, uint64_t offset);
KINEMIUM_API bool Kinemium_GPUComputeReadBuffer(Kinemium_Context *context, uint32_t buffer_id, uint64_t offset, uint64_t bytes, void *output, uint64_t capacity);
KINEMIUM_API bool Kinemium_GPUComputeCopyBuffer(Kinemium_Context *context, uint32_t source_id, uint32_t destination_id, uint64_t bytes, uint64_t source_offset, uint64_t destination_offset);
KINEMIUM_API bool Kinemium_GPUComputeFillBuffer(Kinemium_Context *context, uint32_t buffer_id, uint32_t value, uint64_t bytes, uint64_t offset);
KINEMIUM_API bool Kinemium_GPUComputeCreatePipeline(Kinemium_Context *context, const char *glsl_source, uint32_t binding_count, const uint32_t *binding_kinds, uint32_t *pipeline_id);
KINEMIUM_API bool Kinemium_GPUComputeUsePipeline(Kinemium_Context *context, uint32_t pipeline_id);
KINEMIUM_API bool Kinemium_GPUComputeDestroyPipeline(Kinemium_Context *context, uint32_t pipeline_id);
KINEMIUM_API bool Kinemium_GPUComputeBindBuffer(Kinemium_Context *context, uint32_t binding, uint32_t buffer_id);
KINEMIUM_API bool Kinemium_GPUComputeUnbind(Kinemium_Context *context, uint32_t binding);
KINEMIUM_API bool Kinemium_GPUComputeSetPushConstants(Kinemium_Context *context, const void *data, uint64_t bytes);
KINEMIUM_API bool Kinemium_GPUComputeDispatch(Kinemium_Context *context, uint32_t x, uint32_t y, uint32_t z);
KINEMIUM_API bool Kinemium_GPUComputePoll(Kinemium_Context *context, bool *completed);
KINEMIUM_API bool Kinemium_GPUComputeBeginCommands(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_GPUComputeSubmitCommands(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_GPUComputeCancelCommands(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_GPUComputeBarrier(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_GPUComputeBeginTask(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_GPUComputeSubmitTask(Kinemium_Context *context, uint32_t x, uint32_t y, uint32_t z, uint32_t *task_id);
KINEMIUM_API bool Kinemium_GPUComputeSubmitTaskBatch(Kinemium_Context *context, uint32_t *task_id);
KINEMIUM_API bool Kinemium_GPUComputePollTask(Kinemium_Context *context, uint32_t task_id, bool *completed);
KINEMIUM_API bool Kinemium_GPUComputeGetTaskInfo(Kinemium_Context *context, uint32_t task_id, Kinemium_GPUComputeTaskInfo *output);
KINEMIUM_API uint32_t Kinemium_GPUComputePendingTaskCount(Kinemium_Context *context);
KINEMIUM_API bool Kinemium_GPUComputeCreateTexture(Kinemium_Context *context, const Kinemium_GPUComputeTextureDesc *desc, const void *pixels, uint64_t pixel_bytes, uint32_t *texture_id);
KINEMIUM_API bool Kinemium_GPUComputeGetTextureInfo(Kinemium_Context *context, uint32_t texture_id, Kinemium_GPUComputeTextureInfo *output);
KINEMIUM_API bool Kinemium_GPUComputeBindTexture(Kinemium_Context *context, uint32_t binding, uint32_t texture_id);
KINEMIUM_API bool Kinemium_GPUComputeDestroyTexture(Kinemium_Context *context, uint32_t texture_id);
KINEMIUM_API bool Kinemium_GPUComputeDispatchMaterialTexture(Kinemium_Context *context, Kinemium_Handle material_variant, const char *sampler_name, const char *glsl_source, uint32_t width, uint32_t height);
KINEMIUM_API bool Kinemium_GPUComputeGetRenderStats(Kinemium_GPUComputeRenderStats *output);

#ifdef __cplusplus
}
#endif
#endif

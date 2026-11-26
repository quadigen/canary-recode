#ifndef KINEMIUM_PLUGIN_H
#define KINEMIUM_PLUGIN_H

#include "kinemium.h"

#ifdef __cplusplus
extern "C" {
#define KINEMIUM_ZERO_INIT {}
#else
#define KINEMIUM_ZERO_INIT {0}
#endif

#define KINEMIUM_PLUGIN_ABI_MAJOR KINEMIUM_ABI_MAJOR
#define KINEMIUM_PLUGIN_ABI_MINOR KINEMIUM_ABI_MINOR

#if defined(_WIN32)
#define KINEMIUM_PLUGIN_EXPORT __declspec(dllexport)
#else
#define KINEMIUM_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

typedef bool (*Kinemium_PluginLoadCallback)(Kinemium_Context *context);
typedef void (*Kinemium_PluginUpdateCallback)(Kinemium_Context *context, double dt);
typedef void (*Kinemium_PluginStopCallback)(Kinemium_Context *context);

typedef struct Kinemium_PluginDescriptor {
    uint32_t size;
    uint32_t abi_major;
    uint32_t abi_minor;
    const char *id;
    const char *name;
    const char *version;
    Kinemium_PluginLoadCallback on_load;
    Kinemium_PluginLoadCallback on_start;
    Kinemium_PluginUpdateCallback on_update;
    Kinemium_PluginStopCallback on_stop;
    Kinemium_PluginStopCallback on_unload;
} Kinemium_PluginDescriptor;

static inline Kinemium_ClassDesc Kinemium_Class(const char *name, const char *base, uint64_t data_size) {
    Kinemium_ClassDesc desc = KINEMIUM_ZERO_INIT;
    desc.size = sizeof(desc);
    desc.flags = KINEMIUM_CLASS_CREATABLE;
    desc.name = name;
    desc.base = base;
    desc.data_size = data_size;
    return desc;
}

static inline Kinemium_ServiceDesc Kinemium_Service(const char *name, uint64_t data_size) {
    Kinemium_ServiceDesc desc = Kinemium_Class(name, "Service", data_size);
    desc.flags = KINEMIUM_CLASS_SERVICE;
    return desc;
}

static inline bool Kinemium_ClassProperty(Kinemium_ClassDesc *desc, const char *name,
                                            Kinemium_PropertyKind kind, uint64_t offset) {
    if (!desc || !name || desc->property_count >= KINEMIUM_CLASS_MAX_PROPERTIES) return false;
    Kinemium_ClassPropertyDesc *prop = &desc->properties[desc->property_count++];
    prop->name = name;
    prop->kind = kind;
    prop->offset = offset;
    return true;
}

static inline bool Kinemium_ClassMethod(Kinemium_ClassDesc *desc, const char *name,
                                          Kinemium_ClassMethodFn callback) {
    if (!desc || !name || !callback || desc->method_count >= KINEMIUM_CLASS_MAX_METHODS) return false;
    Kinemium_ClassMethodDesc *method = &desc->methods[desc->method_count++];
    method->name = name;
    method->callback = callback;
    return true;
}

static inline Kinemium_DatatypeDesc Kinemium_Datatype(const char *name, uint64_t data_size) {
    Kinemium_DatatypeDesc desc = KINEMIUM_ZERO_INIT;
    desc.size = sizeof(desc);
    desc.name = name;
    desc.data_size = data_size;
    return desc;
}

static inline bool Kinemium_DatatypeField(Kinemium_DatatypeDesc *desc, const char *name,
                                          Kinemium_PropertyKind kind, uint64_t offset) {
    if (!desc || !name || desc->property_count >= KINEMIUM_CLASS_MAX_PROPERTIES) return false;
    Kinemium_ClassPropertyDesc *prop = &desc->properties[desc->property_count++];
    prop->name = name;
    prop->kind = kind;
    prop->offset = offset;
    return true;
}

static inline bool Kinemium_DatatypeMethod(Kinemium_DatatypeDesc *desc, const char *name,
                                            Kinemium_ClassMethodFn callback) {
    if (!desc || !name || !callback || desc->method_count >= KINEMIUM_CLASS_MAX_METHODS) return false;
    Kinemium_ClassMethodDesc *method = &desc->methods[desc->method_count++];
    method->name = name;
    method->callback = callback;
    return true;
}

KINEMIUM_PLUGIN_EXPORT const Kinemium_PluginDescriptor *Kinemium_PluginEntry(void);

#ifdef __cplusplus
}
#endif

#endif

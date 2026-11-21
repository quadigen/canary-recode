#ifndef KNE_PLUGIN_H
#define KNE_PLUGIN_H

/* Author-facing convenience API. Includes the unchanged low-level ABI. */
#include "kne.h"
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct kne_plugin {
    const kne_host *host;
    kne_extension handle;
} kne_plugin;

static inline kne_plugin kne_make_plugin(const kne_host *host, kne_extension handle) {
    kne_plugin p = {host, handle};
    return p;
}
static inline kne_string kne_text(const char *text) {
    kne_string value = {text, text ? strlen(text) : 0};
    return value;
}
static inline kne_extension_desc kne_make_descriptor(const char *id, const char *name, const char *version, const char *author) {
    kne_extension_desc d;
    memset(&d, 0, sizeof(d));
    d.size = sizeof(d); d.abi_major = KNE_ABI_MAJOR; d.abi_minor = KNE_ABI_MINOR;
    d.id = kne_text(id); d.name = kne_text(name); d.version = kne_text(version); d.author = kne_text(author);
    return d;
}
static inline kne_class_desc kne_make_class(const char *name, const char *base, uint32_t flags) {
    kne_class_desc d;
    memset(&d, 0, sizeof(d));
    d.size = sizeof(d); d.version = KNE_ABI_MAJOR; d.name = kne_text(name); d.base = kne_text(base); d.flags = flags;
    return d;
}
static inline kne_value kne_value_nil(void) {
    kne_value v;
    memset(&v, 0, sizeof(v)); v.kind = KNE_VALUE_NIL; return v;
}
static inline kne_value kne_value_boolean(int32_t x) {
    kne_value v = kne_value_nil(); v.kind = KNE_VALUE_BOOLEAN; v.data.boolean = x != 0; return v;
}
static inline kne_value kne_value_number(double x) {
    kne_value v = kne_value_nil(); v.kind = KNE_VALUE_NUMBER; v.data.number = x; return v;
}
static inline kne_value kne_value_integer(int64_t x) {
    kne_value v = kne_value_nil(); v.kind = KNE_VALUE_INTEGER; v.data.integer = x; return v;
}
static inline kne_value kne_value_string(const char * x) {
    kne_value v = kne_value_nil(); v.kind = KNE_VALUE_STRING; v.data.string = kne_text(x); return v;
}
static inline kne_value kne_value_instance(kne_instance x) {
    kne_value v = kne_value_nil(); if (!x) return v; v.kind = KNE_VALUE_INSTANCE; v.data.instance = x; return v;
}
static inline kne_value kne_value_vector2(kne_vector2 x) {
    kne_value v = kne_value_nil(); v.kind = KNE_VALUE_VECTOR2; v.data.vector2 = x; return v;
}
static inline kne_value kne_value_vector3(kne_vector3 x) {
    kne_value v = kne_value_nil(); v.kind = KNE_VALUE_VECTOR3; v.data.vector3 = x; return v;
}
static inline kne_value kne_value_color3(kne_color3 x) {
    kne_value v = kne_value_nil(); v.kind = KNE_VALUE_COLOR3; v.data.color3 = x; return v;
}
static inline kne_value kne_value_cframe(kne_cframe x) {
    kne_value v = kne_value_nil(); v.kind = KNE_VALUE_CFRAME; v.data.cframe = x; return v;
}

/* Handles and borrowed values are valid only as described by the native ABI.
 * All methods require a valid plugin context on the owning engine thread. */
static inline kne_instance kne_get_service(kne_plugin p, const char *name) {
    return p.host->services->get(p.handle, kne_text(name));
}
static inline int32_t kne_has_service(kne_plugin p, const char *name) {
    return p.host->services->exists(p.handle, kne_text(name));
}
static inline size_t kne_service_count(kne_plugin p) {
    return p.host->services->count(p.handle);
}
static inline kne_string kne_service_name(kne_plugin p, size_t index) {
    return p.host->services->name_at(p.handle, index);
}
static inline kne_instance kne_new_instance(kne_plugin p, const char *class_name) {
    return p.host->instances->create(p.handle, kne_text(class_name));
}
static inline void kne_destroy_instance(kne_plugin p, kne_instance object) {
    p.host->instances->destroy(p.handle, object);
}
static inline kne_string kne_get_name(kne_plugin p, kne_instance object) {
    return p.host->instances->get_name(p.handle, object);
}
static inline void kne_set_name(kne_plugin p, kne_instance object, const char *name) {
    p.host->instances->set_name(p.handle, object, kne_text(name));
}
static inline kne_instance kne_get_parent(kne_plugin p, kne_instance object) {
    return p.host->instances->get_parent(p.handle, object);
}
static inline void kne_set_parent(kne_plugin p, kne_instance object, kne_instance parent) {
    p.host->instances->set_parent(p.handle, object, parent);
}
static inline size_t kne_child_count(kne_plugin p, kne_instance object) {
    return p.host->instances->child_count(p.handle, object);
}
static inline kne_instance kne_child_at(kne_plugin p, kne_instance object, size_t index) {
    return p.host->instances->child_at(p.handle, object, index);
}
static inline kne_instance kne_find_child(kne_plugin p, kne_instance object, const char *name) {
    return p.host->instances->find_child(p.handle, object, kne_text(name));
}
static inline int32_t kne_is_a(kne_plugin p, kne_instance object, const char *name) {
    return p.host->instances->is_a(p.handle, object, kne_text(name));
}
static inline kne_string kne_class_name(kne_plugin p, kne_instance object) {
    return p.host->instances->class_name(p.handle, object);
}
static inline int32_t kne_get_property(kne_plugin p, kne_instance object, const char *name, kne_value *out) {
    return p.host->instances->get_property(p.handle, object, kne_text(name), out);
}
static inline int32_t kne_set_property(kne_plugin p, kne_instance object, const char *name, kne_value value) {
    return p.host->instances->set_property(p.handle, object, kne_text(name), &value);
}
static inline void * kne_get_user_data(kne_plugin p, kne_instance object) {
    return p.host->instances->get_user_data(p.handle, object);
}
static inline void kne_set_user_data(kne_plugin p, kne_instance object, void *data) {
    p.host->instances->set_user_data(p.handle, object, data);
}
static inline int32_t kne_call_method(kne_plugin p, kne_instance object, const char *name, const kne_value *args, int32_t count, kne_value *out, int32_t capacity) {
    return p.host->instances->invoke(p.handle, object, kne_text(name), args, count, out, capacity);
}
static inline int32_t kne_register_class(kne_plugin p, const kne_class_desc *desc) {
    return p.host->classes->register_class(p.handle, desc);
}
static inline int32_t kne_has_class(kne_plugin p, const char *name) {
    return p.host->classes->is_registered(p.handle, kne_text(name));
}
static inline int32_t kne_register_function(kne_plugin p, const char *name, kne_vm_native_fn fn) {
    return p.host->vm->register_function(p.handle, kne_text(name), fn);
}
static inline int32_t kne_register_library_function(kne_plugin p, const char *library, const char *name, kne_vm_native_fn fn) {
    return p.host->vm->register_library_function(p.handle, kne_text(library), kne_text(name), fn);
}
static inline int32_t kne_argument_count(kne_plugin p, kne_vm vm) {
    return p.host->vm->arg_count(vm);
}
static inline int32_t kne_get_argument(kne_plugin p, kne_vm vm, int32_t index, kne_value *out) {
    return p.host->vm->get_value(p.handle, vm, index, out);
}
static inline void kne_push_result(kne_plugin p, kne_vm vm, kne_value value) {
    p.host->vm->push_value(p.handle, vm, &value);
}
static inline int32_t kne_raise_error(kne_plugin p, kne_vm vm, const char *message) {
    return p.host->vm->raise(vm, kne_text(message));
}
static inline kne_string kne_last_error(kne_plugin p) {
    return p.host->core->last_error(p.handle);
}
static inline void kne_log(kne_plugin p, kne_log_level level, const char *message) {
    p.host->core->log(p.handle, level, kne_text(message));
}
static inline kne_signal kne_get_signal(kne_plugin p, kne_instance object, const char *event) {
    return p.host->signals->get(p.handle, object, kne_text(event));
}
static inline kne_connection kne_connect(kne_plugin p, kne_signal signal, kne_signal_native_fn fn) {
    return p.host->signals->connect_native(p.handle, signal, fn);
}
static inline kne_connection kne_connect_once(kne_plugin p, kne_signal signal, kne_signal_native_fn fn) {
    return p.host->signals->once_native(p.handle, signal, fn);
}
static inline void kne_disconnect(kne_plugin p, kne_connection connection) {
    p.host->signals->disconnect(p.handle, connection);
}
static inline int32_t kne_is_connected(kne_plugin p, kne_connection connection) {
    return p.host->signals->is_connected(p.handle, connection);
}
static inline int32_t kne_fire_signal(kne_plugin p, kne_signal signal, const kne_value *args, int32_t count) {
    return p.host->signals->fire(p.handle, signal, args, count);
}
static inline kne_callback kne_retain_callback(kne_plugin p, kne_vm vm, int32_t index) {
    return p.host->callbacks->retain(p.handle, vm, index);
}
static inline void kne_release_callback(kne_plugin p, kne_callback cb) {
    p.host->callbacks->release(p.handle, cb);
}
static inline int32_t kne_call_callback(kne_plugin p, kne_callback cb, const kne_value *args, int32_t count, kne_value *out, int32_t capacity) {
    return p.host->callbacks->call(p.handle, cb, args, count, out, capacity);
}
static inline int32_t kne_new_datatype(kne_plugin p, const char *name, const kne_value *args, int32_t count, kne_value *out) {
    return p.host->datatypes->construct(p.handle, kne_text(name), args, count, out);
}
static inline int32_t kne_get_field(kne_plugin p, kne_value value, const char *name, kne_value *out) {
    return p.host->datatypes->get_field(p.handle, &value, kne_text(name), out);
}
static inline int32_t kne_set_field(kne_plugin p, kne_value value, const char *name, kne_value input) {
    return p.host->datatypes->set_field(p.handle, &value, kne_text(name), &input);
}
static inline int32_t kne_call_datatype_method(kne_plugin p, kne_value value, const char *name, const kne_value *args, int32_t count, kne_value *out, int32_t capacity) {
    return p.host->datatypes->call(p.handle, &value, kne_text(name), args, count, out, capacity);
}
static inline int32_t kne_register_datatype(kne_plugin p, const kne_datatype_desc *desc) {
    return p.host->datatypes->register_datatype(p.handle, desc);
}
static inline int32_t kne_has_export(kne_plugin p, kne_instance object, const char *name) {
    return p.host->exports->exists(p.handle, object, kne_text(name));
}
static inline int32_t kne_call_export(kne_plugin p, kne_instance object, const char *name, const kne_value *args, int32_t count, kne_value *out, int32_t capacity) {
    return p.host->exports->call(p.handle, object, kne_text(name), args, count, out, capacity);
}
static inline int32_t kne_run_luau(kne_plugin p, const char *source, const kne_value *args, int32_t count, kne_value *out, int32_t capacity) {
    if (p.host->abi_minor < 1 || p.host->vm->size < sizeof(kne_vm_api) || !p.host->vm->execute) return -1;
    return p.host->vm->execute(p.handle, kne_text(source), args, count, out, capacity);
}

static inline void *kne_get_buffer(kne_plugin p, kne_vm vm, int32_t index, size_t *size) {
    if (size) *size = 0;
    if (p.host->abi_minor < 1 || p.host->vm->size < sizeof(kne_vm_api) || !p.host->vm->get_buffer) return NULL;
    return p.host->vm->get_buffer(vm, index, size);
}
static inline int32_t kne_push_buffer(kne_plugin p, kne_vm vm, const void *data, size_t size) {
    if (p.host->abi_minor < 1 || p.host->vm->size < sizeof(kne_vm_api) || !p.host->vm->push_buffer) return 0;
    return p.host->vm->push_buffer(vm, data, size);
}
static inline kne_connection kne_connect_callback(kne_plugin p, kne_signal signal, kne_callback callback) {
    return p.host->signals->connect_callback(p.handle, signal, callback);
}
static inline kne_connection kne_connect_callback_once(kne_plugin p, kne_signal signal, kne_callback callback) {
    return p.host->signals->once_callback(p.handle, signal, callback);
}
static inline int32_t kne_is_callback_valid(kne_plugin p, kne_callback callback) {
    return p.host->callbacks->is_valid(p.handle, callback);
}
static inline int32_t kne_has_datatype(kne_plugin p, const char *name) {
    return p.host->datatypes->is_registered(p.handle, kne_text(name));
}
static inline int32_t kne_unregister_datatype(kne_plugin p, const char *name) {
    return p.host->datatypes->unregister_datatype(p.handle, kne_text(name));
}

#ifdef __cplusplus
}
#endif
#endif

#ifndef KNE_H
#define KNE_H

#include "kne_types.h"
#include "modules/core.h"
#include "modules/services.h"
#include "modules/classes.h"
#include "modules/instances.h"
#include "modules/vm.h"
#include "modules/datatypes.h"
#include "modules/callbacks.h"
#include "modules/signals.h"
#include "modules/exports.h"

#ifdef __cplusplus
extern "C" {
#endif

#define KNE_ABI_MAJOR 2u
#define KNE_ABI_MINOR 0u
#define KNE_ENTRY_SYMBOL "kne_extension_entry"

typedef struct kne_host {
	uint32_t size;
	uint32_t abi_major;
	uint32_t abi_minor;
	uint32_t reserved;
	kne_string engine_name;
	kne_string engine_version;
	const kne_core_api *core;
	const kne_services_api *services;
	const kne_classes_api *classes;
	const kne_instances_api *instances;
	const kne_vm_api *vm;
	const kne_datatypes_api *datatypes;
	const kne_callbacks_api *callbacks;
	const kne_signals_api *signals;
	const kne_exports_api *exports;
} kne_host;

typedef int32_t (KNE_CALL *kne_extension_load_fn)(kne_extension ext);
typedef int32_t (KNE_CALL *kne_extension_start_fn)(kne_extension ext);
typedef void (KNE_CALL *kne_extension_stop_fn)(kne_extension ext);
typedef void (KNE_CALL *kne_extension_unload_fn)(kne_extension ext);
typedef void (KNE_CALL *kne_extension_update_fn)(kne_extension ext, double delta_time);

typedef struct kne_extension_desc {
	uint32_t size;
	uint32_t abi_major;
	uint32_t abi_minor;
	uint32_t flags;
	kne_string id;
	kne_string name;
	kne_string version;
	kne_string author;
	kne_extension_load_fn on_load;
	kne_extension_start_fn on_start;
	kne_extension_stop_fn on_stop;
	kne_extension_unload_fn on_unload;
	kne_extension_update_fn on_update;
} kne_extension_desc;

typedef const kne_extension_desc *(KNE_CALL *kne_entry_fn)(const kne_host *host);

#ifdef __cplusplus
}
#endif

#endif

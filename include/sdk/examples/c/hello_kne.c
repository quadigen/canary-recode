#include "kne.h"

#include <string.h>

#define KS(lit) { lit, sizeof(lit) - 1 }

static const kne_host *g_host = NULL;

static int32_t KNE_CALL calculate(kne_extension ext, kne_vm vm) {
	const kne_vm_api *api = g_host->vm;
	if (api == NULL) {
		return 0;
	}
	api->push_number(vm, api->get_number(vm, 1) + api->get_number(vm, 2));
	return 1;
}

static int32_t KNE_CALL greeting(kne_extension ext, kne_vm vm) {
	const kne_vm_api *api = g_host->vm;
	kne_string who;
	char buffer[256];
	size_t used = 0;
	size_t kept;

	if (api == NULL) {
		return 0;
	}

	who = api->get_string(vm, 1);
	kept = who.length;
	if (kept > sizeof(buffer) - 8) {
		kept = sizeof(buffer) - 8;
	}

	memcpy(buffer, "hello ", 6);
	used = 6;
	if (kept > 0 && who.data != NULL) {
		memcpy(buffer + used, who.data, kept);
		used += kept;
	}

	{
		kne_string result = { buffer, used };
		api->push_string(vm, result);
	}
	return 1;
}

/* Retain a Luau function, invoke it with one numeric value, then release it. */
static int32_t KNE_CALL apply_callback(kne_extension ext, kne_vm vm) {
 kne_callback callback = g_host->callbacks->retain(ext, vm, 1);
 kne_value arg = {0}, out = {0};
 int32_t count;
 if (!callback) return 0;
 arg.kind = KNE_VALUE_NUMBER;
 arg.data.number = g_host->vm->get_number(vm, 2);
 count = g_host->callbacks->call(ext, callback, &arg, 1, &out, 1);
 g_host->callbacks->release(ext, callback);
 if (count != 1) return 0;
 return g_host->datatypes->push(ext, vm, &out) ? 1 : 0;
}

static int32_t KNE_CALL on_load(kne_extension ext) {
	const kne_vm_api *api = g_host->vm;

	if (!g_host->callbacks || !g_host->datatypes) return 0;
	if (api == NULL || api->register_library_function == NULL) {
		return 0;
	}
	if (!api->register_library_function(ext, (kne_string)KS("HelloKNEC"), (kne_string)KS("ApplyCallback"), apply_callback)) return 0;
	if (!api->register_library_function(ext, (kne_string)KS("HelloKNEC"), (kne_string)KS("Calculate"), calculate)) {
		return 0;
	}
	if (!api->register_library_function(ext, (kne_string)KS("HelloKNEC"), (kne_string)KS("Greeting"), greeting)) {
		return 0;
	}
	return 1;
}

static void KNE_CALL on_update(kne_extension ext, double delta_time) {
	(void)ext;
	(void)delta_time;
}

static const kne_extension_desc g_desc = {
	sizeof(kne_extension_desc),
	KNE_ABI_MAJOR,
	KNE_ABI_MINOR,
	0,
	KS("kne.hello.c"),
	KS("Hello KNE (C)"),
	KS("1.0.0"),
	KS("Kinemium"),
	on_load,
	NULL,
	NULL,
	NULL,
	on_update,
};

KNE_EXPORT const kne_extension_desc *KNE_CALL kne_extension_entry(const kne_host *host) {
	g_host = host;
	return &g_desc;
}

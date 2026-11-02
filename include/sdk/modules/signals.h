#ifndef KNE_MODULE_SIGNALS_H
#define KNE_MODULE_SIGNALS_H

#include "../kne_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (KNE_CALL *kne_signal_native_fn)(kne_extension ext, kne_vm vm);

/* Resolves a signal property on an Instance. Returns NULL when the property is
 * missing or is not a signal. */
typedef kne_signal (KNE_CALL *kne_get_signal_fn)(kne_extension ext, kne_instance instance, kne_string property);
typedef kne_connection (KNE_CALL *kne_connect_native_fn)(kne_extension ext, kne_signal signal, kne_signal_native_fn callback);
typedef kne_connection (KNE_CALL *kne_connect_callback_fn)(kne_extension ext, kne_signal signal, kne_callback callback);
typedef kne_connection (KNE_CALL *kne_once_native_fn)(kne_extension ext, kne_signal signal, kne_signal_native_fn callback);
typedef kne_connection (KNE_CALL *kne_once_callback_fn)(kne_extension ext, kne_signal signal, kne_callback callback);
typedef void (KNE_CALL *kne_disconnect_fn)(kne_extension ext, kne_connection connection);
typedef int32_t (KNE_CALL *kne_signal_fire_fn)(kne_extension ext, kne_signal signal, const kne_value *args, int32_t arg_count);
typedef int32_t (KNE_CALL *kne_connection_connected_fn)(kne_extension ext, kne_connection connection);

typedef struct kne_signals_api {
	uint32_t size;
	uint32_t version;
	kne_get_signal_fn get;
	kne_connect_native_fn connect_native;
	kne_connect_callback_fn connect_callback;
	kne_once_native_fn once_native;
	kne_once_callback_fn once_callback;
	kne_disconnect_fn disconnect;
	kne_signal_fire_fn fire;
	kne_connection_connected_fn is_connected;
} kne_signals_api;

#ifdef __cplusplus
}
#endif

#endif


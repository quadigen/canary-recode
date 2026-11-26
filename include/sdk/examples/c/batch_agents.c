#include "kne_plugin.h"
#include <stddef.h>

static const kne_host *host;
typedef struct agent_state { double position, velocity; } agent_state;

static void KNE_CALL construct_agent(kne_extension ext, kne_instance instance) {
    agent_state *state = (agent_state *)host->core->allocate(ext, sizeof(*state));
    if (state) { state->position = 0; state->velocity = 1; }
    host->instances->set_user_data(ext, instance, state);
}
static void KNE_CALL destroy_agent(kne_extension ext, kne_instance instance) {
    void *state = host->instances->get_user_data(ext, instance);
    host->instances->set_user_data(ext, instance, NULL);
    host->core->release(ext, state);
}
static void KNE_CALL step_agent(kne_extension ext, kne_instance instance, double dt) {
    agent_state *state = (agent_state *)host->instances->get_user_data(ext, instance);
    if (state) state->position += state->velocity * dt;
}
static void KNE_CALL step_agents(kne_extension ext, const kne_batch_instance *view, uintptr_t count, double dt) {
    uintptr_t i;
    (void)ext;
    for (i = 0; i < count; ++i) {
        agent_state *state = (agent_state *)view[i].user_data;
        if (state) state->position += state->velocity * dt;
    }
}
static int32_t KNE_CALL load(kne_extension ext) {
    kne_class_desc desc = kne_make_class("BatchAgent", "Instance", KNE_CLASS_CREATABLE);
    desc.on_construct = construct_agent;
    desc.on_destroy = destroy_agent;
    desc.step = step_agent;
    if (host->abi_minor >= 2) desc.step_batch = step_agents;
    return host->classes->register_class(ext, &desc);
}
static kne_extension_desc descriptor;
KNE_EXPORT const kne_extension_desc *KNE_CALL kne_extension_entry(const kne_host *engine) {
    host = engine;
    descriptor = kne_make_descriptor("kne.batch-agents", "Batched agents", "1.0.0", "Kinemium");
    /* A 3.1 host reads the known prefix and invokes step instead. */
    descriptor.abi_minor = engine->abi_minor >= 2 ? 2 : 1;
    descriptor.on_load = load;
    return &descriptor;
}

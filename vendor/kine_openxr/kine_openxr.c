#include "kine_openxr.h"
#include <openxr/openxr.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
struct KineXRContext {
    XrInstance instance;
    XrSystemId system;
    XrSystemProperties properties;
    uint32_t view_count;
    XrViewConfigurationView *views;
};
static _Thread_local char error_text[512];
static void fail(const char *text, XrResult result) {
    snprintf(error_text, sizeof(error_text), "%s (OpenXR result %d)", text, (int)result);
}
const char *Kine_XR_GetLastError(void) { return error_text; }
void Kine_XR_Destroy(KineXRContext *ctx) {
    if (!ctx) return;
    free(ctx->views);
    if (ctx->instance != XR_NULL_HANDLE) xrDestroyInstance(ctx->instance);
    free(ctx);
}
KineXRContext *Kine_XR_Create(const char *app) {
    error_text[0] = 0;
    KineXRContext *ctx = (KineXRContext *)calloc(1, sizeof(*ctx));
    if (!ctx) { fail("Out of memory", XR_ERROR_OUT_OF_MEMORY); return NULL; }
    XrInstanceCreateInfo info = {XR_TYPE_INSTANCE_CREATE_INFO};
    snprintf(info.applicationInfo.applicationName, XR_MAX_APPLICATION_NAME_SIZE,
             "%s", app && *app ? app : "Kinemium");
    snprintf(info.applicationInfo.engineName, XR_MAX_ENGINE_NAME_SIZE, "%s", "Kinemium");
    info.applicationInfo.applicationVersion = 1;
    info.applicationInfo.engineVersion = 1;
    info.applicationInfo.apiVersion = XR_CURRENT_API_VERSION;
    XrResult r = xrCreateInstance(&info, &ctx->instance);
    if (XR_FAILED(r)) { fail("Cannot create OpenXR instance; check XR_RUNTIME_JSON", r); goto error; }
    XrSystemGetInfo system_info = {XR_TYPE_SYSTEM_GET_INFO};
    system_info.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    r = xrGetSystem(ctx->instance, &system_info, &ctx->system);
    if (XR_FAILED(r)) { fail("No real or simulated OpenXR HMD found", r); goto error; }
    ctx->properties.type = XR_TYPE_SYSTEM_PROPERTIES;
    r = xrGetSystemProperties(ctx->instance, ctx->system, &ctx->properties);
    if (XR_FAILED(r)) { fail("Cannot query OpenXR system", r); goto error; }
    r = xrEnumerateViewConfigurationViews(ctx->instance, ctx->system,
        XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0, &ctx->view_count, NULL);
    if (XR_FAILED(r) || !ctx->view_count) { fail("Stereo views unavailable", r); goto error; }
    ctx->views = (XrViewConfigurationView *)calloc(ctx->view_count, sizeof(*ctx->views));
    if (!ctx->views) { fail("Out of memory", XR_ERROR_OUT_OF_MEMORY); goto error; }
    for (uint32_t i = 0; i < ctx->view_count; i++)
        ctx->views[i].type = XR_TYPE_VIEW_CONFIGURATION_VIEW;
    r = xrEnumerateViewConfigurationViews(ctx->instance, ctx->system,
        XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, ctx->view_count,
        &ctx->view_count, ctx->views);
    if (XR_FAILED(r)) { fail("Cannot query stereo view configuration", r); goto error; }
    return ctx;
error:
    Kine_XR_Destroy(ctx);
    return NULL;
}
uint32_t Kine_XR_GetViewCount(const KineXRContext *ctx) { return ctx ? ctx->view_count : 0; }
int Kine_XR_GetViewInfo(const KineXRContext *ctx, uint32_t index, KineXRViewInfo *out) {
    if (!ctx || !out || index >= ctx->view_count) return 0;
    const XrViewConfigurationView *v = &ctx->views[index];
    *out = (KineXRViewInfo){v->recommendedImageRectWidth,
        v->recommendedImageRectHeight, v->recommendedSwapchainSampleCount,
        v->maxImageRectWidth, v->maxImageRectHeight};
    return 1;
}
uint32_t Kine_XR_GetVendorId(const KineXRContext *ctx) { return ctx ? ctx->properties.vendorId : 0; }
const char *Kine_XR_GetSystemName(const KineXRContext *ctx) {
    return ctx ? ctx->properties.systemName : "";
}

#ifndef KINE_OPENXR_H
#define KINE_OPENXR_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct KineXRContext KineXRContext;
typedef struct KineXRViewInfo {
    uint32_t recommended_width, recommended_height, recommended_samples;
    uint32_t maximum_width, maximum_height;
} KineXRViewInfo;
KineXRContext *Kine_XR_Create(const char *application_name);
void Kine_XR_Destroy(KineXRContext *ctx);
const char *Kine_XR_GetLastError(void);
uint32_t Kine_XR_GetViewCount(const KineXRContext *ctx);
int Kine_XR_GetViewInfo(const KineXRContext *ctx, uint32_t index, KineXRViewInfo *out);
uint32_t Kine_XR_GetVendorId(const KineXRContext *ctx);
const char *Kine_XR_GetSystemName(const KineXRContext *ctx);
#ifdef __cplusplus
}
#endif
#endif

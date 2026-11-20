#include "kine_openxr.h"
#include <stdio.h>
int main(void) {
    KineXRContext *xr = Kine_XR_Create("Kinemium OpenXR Probe");
    if (!xr) {
        fprintf(stderr, "OpenXR unavailable: %s\n", Kine_XR_GetLastError());
        return 1;
    }
    printf("OpenXR HMD: %s (vendor %u)\n",
        Kine_XR_GetSystemName(xr), Kine_XR_GetVendorId(xr));
    uint32_t n = Kine_XR_GetViewCount(xr);
    printf("Views: %u\n", n);
    for (uint32_t i = 0; i < n; i++) {
        KineXRViewInfo v;
        if (Kine_XR_GetViewInfo(xr, i, &v))
            printf("view %u: %ux%u recommended, %ux%u max, %u samples\n",
                i, v.recommended_width, v.recommended_height,
                v.maximum_width, v.maximum_height, v.recommended_samples);
    }
    Kine_XR_Destroy(xr);
    return 0;
}

#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

struct KineFilamentContext;

void Kine_Filament_SetTerrainGrassOptions(
    struct KineFilamentContext *ctx, bool enabled, float density, float height,
    float visibleDistance, float windStrength, uint32_t materialLayerMask);

#ifdef __cplusplus
}
#endif

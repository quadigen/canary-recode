#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

struct KineFrameBudget {
    float minimum = 0.5f;
    float maximum = 1.0f;
    float scale = 1.0f;
    float smoothedRatio = 1.0f;
    float missedRatio = 0.0f;
    float pressureRatio = 0.0f;
    uint32_t slowFrames = 0;
    uint32_t fastFrames = 0;
    bool configured = false;
    bool enabled = false;

    void configure(bool active, float low, float high) {
        if (configured && enabled == active && minimum == low && maximum == high) return;
        configured = true;
        enabled = active;
        minimum = low;
        maximum = high;
        scale = active ? std::clamp(scale, low, high) : 1.0f;
        smoothedRatio = 1.0f;
        missedRatio = pressureRatio = 0.0f;
        slowFrames = fastFrames = 0;
    }

    bool update(float seconds, float pressureSeconds, float hz) {
        if (!enabled || !std::isfinite(seconds) || !std::isfinite(pressureSeconds) ||
            !std::isfinite(hz) || hz < 20 || seconds <= 0 || seconds > 0.1f) {
            slowFrames = fastFrames = 0;
            return false;
        }
        const float ratio = seconds * hz;
        smoothedRatio += (ratio - smoothedRatio) * 0.125f;
        missedRatio += ((ratio > 1.0f ? 1.0f : 0.0f) - missedRatio) * 0.0625f;
        pressureRatio += (std::clamp(pressureSeconds * hz,0.0f,2.0f) - pressureRatio) * 0.125f;
        const float next = scale;
        if ((smoothedRatio > 0.96f || missedRatio > 0.15f) && pressureRatio > 0.12f) {
            fastFrames = 0;
            if (++slowFrames >= 8) {
                scale = std::max(minimum, scale - 0.0625f);
                slowFrames = 0;
            }
        } else if (smoothedRatio < 0.82f && missedRatio < 0.03f) {
            slowFrames = 0;
            if (++fastFrames >= 180) {
                scale = std::min(maximum, scale + 0.03125f);
                fastFrames = 0;
            }
        } else {
            slowFrames = fastFrames = 0;
        }
        return next != scale;
    }
};

inline uint32_t kine_budget_shadow_size(uint32_t authored, uint32_t current, float scale, bool enabled) {
    if (!enabled || authored <= 256) return authored;
    const uint32_t half = std::max(256u, authored / 2);
    const uint32_t quarter = std::max(256u, authored / 4);
    if (scale <= 0.40f) return quarter;
    if (current == quarter && quarter < half && scale < 0.50f) return quarter;
    if (scale <= 0.75f || (current <= half && scale < 0.90f)) return half;
    return authored;
}

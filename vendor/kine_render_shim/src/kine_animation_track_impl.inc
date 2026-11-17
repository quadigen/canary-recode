/* Implementation deliberately lives in the shim translation unit so it can
 * reuse KineMesh, KineAnimation, interpolation and skin-upload helpers. */

struct KineFilamentAnimationTrack {
    KineFilamentAnimator *animator = nullptr;
    int animationIndex = -1;
    int priority = 0;
    bool looped = false;
    bool playing = false;
    bool stopping = false;
    float position = 0.0f;
    float speed = 1.0f;
    float weightCurrent = 0.0f;
    float weightTarget = 0.0f;
    float fadeFrom = 0.0f;
    float fadeDuration = 0.0f;
    float fadeElapsed = 0.0f;
    int stoppedEvents = 0;
    int endedEvents = 0;
    int loopEvents = 0;
    std::deque<KineClipEvent> emitted;
};

struct KinePoseTRS {
    math::float3 translation{};
    KineQuat rotation{};
    math::float3 scale{1.0f, 1.0f, 1.0f};
};

struct KinePoseAccum {
    math::float3 translationSum{};
    math::float3 scaleSum{};
    KineQuat rotationSum{0, 0, 0, 0};
    KineQuat rotationReference{};
    float translationWeight = 0.0f;
    float scaleWeight = 0.0f;
    float rotationWeight = 0.0f;
};

struct KineFilamentAnimator {
    KineFilamentContext *ctx = nullptr;
    KineMesh *mesh = nullptr;
    std::vector<KineFilamentAnimationTrack *> tracks;
    std::vector<KinePoseTRS> pose;
    std::vector<KinePoseAccum> accum;
    std::vector<math::mat4f> locals;
    std::vector<math::mat4f> globals;
    std::vector<uint8_t> states;
    bool poseDirty = true;
};

namespace {
static bool kine_track_finite(float value) { return std::isfinite(value); }

static bool kine_track_valid(const KineFilamentAnimationTrack *track) {
    return track && track->animator && track->animator->mesh &&
        track->animationIndex >= 0 &&
        (size_t)track->animationIndex < track->animator->mesh->animations.size();
}

static void kine_track_fade_to(KineFilamentAnimationTrack *track, float weight, float seconds) {
    track->fadeFrom = track->weightCurrent;
    track->weightTarget = std::max(weight, 0.0f);
    track->fadeDuration = std::max(seconds, 0.0f);
    track->fadeElapsed = 0.0f;
    if (track->fadeDuration <= 0.0f)
        track->weightCurrent = track->weightTarget;
    track->animator->poseDirty = true;
}

static void kine_track_end(KineFilamentAnimationTrack *track) {
    if (track->stopping || track->playing) {
        track->playing = false;
        track->stopping = true;
        ++track->stoppedEvents;
        kine_track_fade_to(track, 0.0f, 0.1f);
    }
}

static void kine_track_emit_segment(KineFilamentAnimationTrack *track, float from, float to, bool forward) {
    const auto &events = track->animator->mesh->animations[(size_t)track->animationIndex].events;
    for (const auto &event : events) {
        if ((forward && event.time > from && event.time <= to) ||
            (!forward && event.time >= to && event.time < from)) {
            if (track->emitted.size() >= 1024) track->emitted.pop_front();
            track->emitted.push_back(event);
        }
    }
}

static void kine_track_advance(KineFilamentAnimationTrack *track, float dt) {
    if (!kine_track_valid(track)) return;
    const float duration = track->animator->mesh->animations[(size_t)track->animationIndex].duration;
    if (track->playing && dt > 0.0f && track->speed != 0.0f && duration > 0.0f) {
        const double previous = track->position;
        const double next = previous + (double)dt * (double)track->speed;
        if (track->looped) {
            if (next >= duration || next < 0.0) {
                const double cycles = next >= duration
                    ? std::floor(next / duration)
                    : (1.0 + std::floor(-next / duration));
                const int count = (int)std::min(cycles, (double)std::numeric_limits<int>::max() - track->loopEvents);
                track->loopEvents += std::max(0, count);
            }
            const double finalPos = std::fmod(std::fmod(next, (double)duration) + duration, (double)duration);
            const bool forward = track->speed > 0.0f;
            if (forward) {
                if (next >= duration) {
                    kine_track_emit_segment(track, (float)previous, duration, true);
                    const int extra = std::min(32, (int)std::floor((next - duration) / duration));
                    for (int n=0;n<extra;++n) kine_track_emit_segment(track, -0.00001f, duration, true);
                    kine_track_emit_segment(track, -0.00001f, (float)finalPos, true);
                } else kine_track_emit_segment(track, (float)previous, (float)next, true);
            } else {
                if (next < 0.0) {
                    kine_track_emit_segment(track, (float)previous, 0.0f, false);
                    const int extra = std::min(32, (int)std::floor(std::max(0.0, -next - 0.000001) / duration));
                    for (int n=0;n<extra;++n) kine_track_emit_segment(track, duration, 0.0f, false);
                    kine_track_emit_segment(track, duration, (float)finalPos, false);
                } else kine_track_emit_segment(track, (float)previous, (float)next, false);
            }
            track->position = (float)finalPos;
        } else if (next >= duration || next < 0.0) {
            track->position = next >= duration ? duration : 0.0f;
            kine_track_emit_segment(track, (float)previous, track->position, track->speed > 0.0f);
            kine_track_end(track);
        } else {
            track->position = (float)next;
            kine_track_emit_segment(track, (float)previous, track->position, track->speed > 0.0f);
        }
    }
    if (track->fadeDuration > 0.0f && track->fadeElapsed < track->fadeDuration) {
        track->fadeElapsed = std::min(track->fadeDuration, track->fadeElapsed + dt);
        float alpha = track->fadeElapsed / track->fadeDuration;
        track->weightCurrent = track->fadeFrom + (track->weightTarget - track->fadeFrom) * alpha;
    }
    if (track->stopping && track->weightCurrent <= 0.000001f &&
        track->weightTarget <= 0.0f) {
        track->weightCurrent = 0.0f;
        track->stopping = false;
        ++track->endedEvents;
    }
}

static void kine_track_accumulate(KinePoseAccum &acc,
    const KineAnimationChannel &channel, float atTime, float weight) {
    if (!channel.translations.empty()) {
        acc.translationSum += kine_sample_vec(channel.translations, atTime, {}) * weight;
        acc.translationWeight += weight;
    }
    if (!channel.scales.empty()) {
        acc.scaleSum += kine_sample_vec(channel.scales, atTime, {1,1,1}) * weight;
        acc.scaleWeight += weight;
    }
    if (!channel.rotations.empty()) {
        KineQuat q = kine_normalize_quat(kine_sample_quat(channel.rotations, atTime, {}));
        if (acc.rotationWeight == 0.0f) acc.rotationReference = q;
        const KineQuat &reference = acc.rotationReference;
        const float dot = q.x * reference.x + q.y * reference.y + q.z * reference.z + q.w * reference.w;
        if (dot < 0.0f) { q.x = -q.x; q.y = -q.y; q.z = -q.z; q.w = -q.w; }
        acc.rotationSum.x += q.x * weight;
        acc.rotationSum.y += q.y * weight;
        acc.rotationSum.z += q.z * weight;
        acc.rotationSum.w += q.w * weight;
        acc.rotationWeight += weight;
    }
}

static bool kine_animator_apply_pose(KineFilamentAnimator *animator) {
    KineMesh *mesh = animator->mesh;
    KineFilamentContext *ctx = animator->ctx;
    if (!ctx || !mesh || mesh->bones.empty()) return false;
    const size_t boneCount = mesh->bones.size();
    for (size_t b = 0; b < boneCount; ++b) {
        animator->pose[b].translation = mesh->bones[b].bindTranslation;
        animator->pose[b].rotation = mesh->bones[b].bindRotation;
        animator->pose[b].scale = mesh->bones[b].bindScale;
    }
    for (int priority = 0; priority <= 6; ++priority) {
        std::fill(animator->accum.begin(), animator->accum.end(), KinePoseAccum{});
        for (const auto *track : animator->tracks) {
            if (!track || !(track->playing || track->stopping) || track->priority != priority ||
                track->weightCurrent <= 0.000001f) continue;
            const auto &clip = mesh->animations[(size_t)track->animationIndex];
            for (const auto &channel : clip.channels) {
                if (channel.bone < 0 || (size_t)channel.bone >= boneCount) continue;
                kine_track_accumulate(animator->accum[(size_t)channel.bone], channel,
                    track->position, track->weightCurrent);
            }
        }
        for (size_t b = 0; b < boneCount; ++b) {
            KinePoseTRS &pose = animator->pose[b];
            const KinePoseAccum &acc = animator->accum[b];
            if (acc.translationWeight > 0.0f) {
                pose.translation = kine_lerp(pose.translation,
                    acc.translationSum / acc.translationWeight,
                    std::min(acc.translationWeight, 1.0f));
            }
            if (acc.scaleWeight > 0.0f) {
                pose.scale = kine_lerp(pose.scale, acc.scaleSum / acc.scaleWeight,
                    std::min(acc.scaleWeight, 1.0f));
            }
            if (acc.rotationWeight > 0.0f) {
                const KineQuat average = kine_normalize_quat(acc.rotationSum);
                pose.rotation = kine_slerp(pose.rotation, average,
                    std::min(acc.rotationWeight, 1.0f));
            }
        }
    }
    for (size_t b = 0; b < boneCount; ++b) {
        const KinePoseTRS &pose = animator->pose[b];
        animator->locals[b] = kine_compose_trs(pose.translation, pose.rotation, pose.scale);
        animator->states[b] = 0;
    }
    for (size_t b = 0; b < boneCount; ++b) {
        if (!kine_eval_bone_global(b, mesh, animator->locals,
                animator->globals, animator->states)) return false;
    }
    mesh->skinMatrices.resize(boneCount);
    for (size_t b = 0; b < boneCount; ++b)
        mesh->skinMatrices[b] = animator->globals[b] * mesh->bones[b].inverseBind;
    kine_upload_skin_pose(ctx, mesh);
    animator->poseDirty = false;
    return true;
}
} // namespace

KINE_API KineFilamentAnimator *Kine_Filament_AnimatorCreate(
    KineFilamentContext *ctx, KineFilamentMesh *mesh) {
    auto *m = reinterpret_cast<KineMesh *>(mesh);
    if (!ctx || !ctx->engine || !m || m->bones.empty() || m->animator) return nullptr;
    auto *animator = new KineFilamentAnimator();
    animator->ctx = ctx;
    animator->mesh = m;
    const size_t count = m->bones.size();
    animator->pose.resize(count);
    animator->accum.resize(count);
    animator->locals.resize(count);
    animator->globals.resize(count);
    animator->states.resize(count);
    m->animator = animator;
    ctx->animationAnimators.push_back(animator);
    return animator;
}

KINE_API void Kine_Filament_AnimatorDestroy(KineFilamentAnimator *animator) {
    if (!animator) return;
    if (animator->mesh && animator->mesh->animator == animator)
        animator->mesh->animator = nullptr;
    if (animator->ctx) {
        auto &all = animator->ctx->animationAnimators;
        all.erase(std::remove(all.begin(), all.end(), animator), all.end());
    }
    for (auto *track : animator->tracks) delete track;
    animator->tracks.clear();
    /* Restore the bind pose if the mesh is still alive. */
    if (animator->mesh && animator->ctx && animator->ctx->engine)
        kine_animator_apply_pose(animator);
    delete animator;
}

KINE_API KineFilamentAnimationTrack *Kine_Filament_AnimatorLoadAnimation(
    KineFilamentAnimator *animator, int animationIndex) {
    if (!animator || !animator->mesh || animationIndex < 0 ||
        (size_t)animationIndex >= animator->mesh->animations.size()) return nullptr;
    auto *track = new KineFilamentAnimationTrack();
    track->animator = animator;
    track->animationIndex = animationIndex;
    animator->tracks.push_back(track);
    return track;
}

KINE_API int Kine_Filament_AnimatorGetTrackCount(const KineFilamentAnimator *animator) {
    return animator ? (int)animator->tracks.size() : 0;
}

KINE_API KineFilamentAnimationTrack *Kine_Filament_AnimatorGetTrack(
    KineFilamentAnimator *animator, int trackIndex) {
    return animator && trackIndex >= 0 && (size_t)trackIndex < animator->tracks.size()
        ? animator->tracks[(size_t)trackIndex] : nullptr;
}

static KineQuat kine_quat_multiply(KineQuat a, KineQuat b) {
    return kine_normalize_quat({
        a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
        a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
        a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w,
        a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z
    });
}

static KineQuat kine_quat_from_rotation(const float *m) {
    const float t = m[3] + m[7] + m[11];
    KineQuat q;
    if (t > 0) {
        float s = std::sqrt(t+1.0f)*2;
        q = {(m[10]-m[8])/s,(m[5]-m[9])/s,(m[6]-m[4])/s,0.25f*s};
    } else if (m[3] > m[7] && m[3] > m[11]) {
        float s=std::sqrt(1+m[3]-m[7]-m[11])*2;
        q={0.25f*s,(m[4]+m[6])/s,(m[5]+m[9])/s,(m[10]-m[8])/s};
    } else if (m[7] > m[11]) {
        float s=std::sqrt(1+m[7]-m[3]-m[11])*2;
        q={(m[4]+m[6])/s,0.25f*s,(m[8]+m[10])/s,(m[5]-m[9])/s};
    } else {
        float s=std::sqrt(1+m[11]-m[3]-m[7])*2;
        q={(m[5]+m[9])/s,(m[8]+m[10])/s,0.25f*s,(m[6]-m[4])/s};
    }
    return kine_normalize_quat(q);
}

KINE_API int Kine_Filament_MeshCreateAnimation(KineFilamentMesh *mesh, const char *name, float duration) {
    auto *m=reinterpret_cast<KineMesh *>(mesh);
    if (!m || !std::isfinite(duration) || duration <= 0.0f || duration > 36000.0f || !name) return -1;
    KineAnimation clip{};
    clip.name=name;
    clip.duration=duration;
    m->animations.push_back(std::move(clip));
    return (int)m->animations.size()-1;
}

KINE_API bool Kine_Filament_MeshAddAnimationPose(KineFilamentMesh *mesh, int clipIndex,
    const char *boneName, float time, const float *cf, float weight) {
    auto *m=reinterpret_cast<KineMesh *>(mesh);
    if (!m || !boneName || !cf || clipIndex < 0 || (size_t)clipIndex >= m->animations.size() ||
        !std::isfinite(time) || time < 0.0f || time > m->animations[(size_t)clipIndex].duration) return false;
    for(int i=0;i<12;++i) if(!std::isfinite(cf[i])) return false;
    if (!std::isfinite(weight) || weight < 0.0f || weight > 1.0f) return false;
    int bone=-1;
    for(size_t i=0;i<m->bones.size();++i) if(m->bones[i].name == boneName){bone=(int)i;break;}
    if(bone<0) return false;
    const auto &bind=m->bones[(size_t)bone];
    KineAnimation &clip=m->animations[(size_t)clipIndex];
    KineAnimationChannel *channel=nullptr;
    for(auto &c:clip.channels) if(c.bone==bone){channel=&c;break;}
    if(!channel) { clip.channels.emplace_back(); channel=&clip.channels.back(); channel->bone=bone; }
    // CFrame is an offset relative to the imported bone's local bind transform.
    const auto offset=math::float3{cf[0],cf[1],cf[2]};
    const KineQuat bindQ=bind.bindRotation;
    const KineQuat localQ=kine_quat_from_rotation(cf);
    const math::mat4f offsetMatrix=kine_compose_trs(offset,localQ,{1,1,1});
    const math::mat4f composed=bind.bindLocal * offsetMatrix;
    // Translation of the product is in column three of the Filament column-major matrix.
    const math::float3 t={composed[3].x,composed[3].y,composed[3].z};
    channel->translations.push_back({time,kine_lerp(bind.bindTranslation,t,weight)});
    channel->rotations.push_back({time,kine_slerp(bindQ,kine_quat_multiply(bindQ,localQ),weight)});
    channel->scales.push_back({time,bind.bindScale});
    auto sorter=[](const auto &a,const auto &b){return a.time<b.time;};
    std::sort(channel->translations.begin(),channel->translations.end(),sorter);
    std::sort(channel->rotations.begin(),channel->rotations.end(),sorter);
    std::sort(channel->scales.begin(),channel->scales.end(),sorter);
    return true;
}

KINE_API bool Kine_Filament_MeshAddAnimationEvent(KineFilamentMesh *mesh, int clipIndex,
    float time, const char *name, const char *parameter, bool marker) {
    auto *m=reinterpret_cast<KineMesh *>(mesh);
    if (!m || clipIndex < 0 || (size_t)clipIndex >= m->animations.size() ||
        !std::isfinite(time) || time < 0.0f || time > m->animations[(size_t)clipIndex].duration || !name) return false;
    auto &clip=m->animations[(size_t)clipIndex];
    clip.events.push_back({time,name,parameter?parameter:"",marker});
    std::stable_sort(clip.events.begin(),clip.events.end(),[](const auto &a,const auto &b){return a.time<b.time;});
    return true;
}

KINE_API float Kine_Filament_MeshGetKeyframeTime(const KineFilamentMesh *mesh, int clipIndex, const char *name) {
    const auto *m=reinterpret_cast<const KineMesh *>(mesh);
    if(!m || !name || clipIndex<0 || (size_t)clipIndex>=m->animations.size()) return -1.0f;
    for(const auto &event:m->animations[(size_t)clipIndex].events) {
        if(!event.marker && event.name==name) return event.time;
    }
    return -1.0f;
}

KINE_API bool Kine_Filament_AnimationTrackPopEvent(KineFilamentAnimationTrack *track, KineAnimationEvent *event) {
    if (!kine_track_valid(track) || !event || track->emitted.empty()) return false;
    const auto hit = track->emitted.front();
    track->emitted.pop_front();
    *event = {};
    event->kind = hit.marker ? 2 : 1;
    event->time = hit.time;
    std::snprintf(event->name, sizeof(event->name), "%s", hit.name.c_str());
    std::snprintf(event->parameter,sizeof(event->parameter),"%s",hit.parameter.c_str());
    return true;
}

KINE_API void Kine_Filament_AnimationTrackDestroy(KineFilamentAnimationTrack *track) {
    if (!track) return;
    if (track->animator) {
        auto *animator = track->animator;
        auto &tracks = animator->tracks;
        tracks.erase(std::remove(tracks.begin(), tracks.end(), track), tracks.end());
        animator->poseDirty = true;
    }
    delete track;
}

KINE_API bool Kine_Filament_AnimationTrackPlay(
    KineFilamentAnimationTrack *track, float fadeTime, float weight, float speed) {
    if (!kine_track_valid(track) || !kine_track_finite(fadeTime) || fadeTime < 0.0f ||
        !kine_track_finite(weight) || weight < 0.0f || !kine_track_finite(speed)) return false;
    const float length = track->animator->mesh->animations[(size_t)track->animationIndex].duration;
    track->playing = true;
    track->stopping = false;
    track->position = speed < 0.0f ? length : 0.0f;
    track->emitted.clear();
    track->speed = speed;
    track->weightCurrent = 0.0f;
    kine_track_fade_to(track, weight, fadeTime);
    return true;
}

KINE_API bool Kine_Filament_AnimationTrackStop(
    KineFilamentAnimationTrack *track, float fadeTime) {
    if (!kine_track_valid(track) || !kine_track_finite(fadeTime) || fadeTime < 0.0f) return false;
    if (track->playing) {
        track->playing = false;
        track->stopping = true;
        ++track->stoppedEvents;
        kine_track_fade_to(track, 0.0f, fadeTime);
        if (fadeTime <= 0.0f) { track->stopping = false; ++track->endedEvents; }
    }
    return true;
}

KINE_API bool Kine_Filament_AnimationTrackAdjustWeight(
    KineFilamentAnimationTrack *track, float weight, float fadeTime) {
    if (!kine_track_valid(track) || !kine_track_finite(weight) || weight < 0.0f ||
        !kine_track_finite(fadeTime) || fadeTime < 0.0f) return false;
    if (track->playing) kine_track_fade_to(track, weight, fadeTime);
    return true;
}

KINE_API bool Kine_Filament_AnimationTrackAdjustSpeed(KineFilamentAnimationTrack *track, float speed) {
    if (!kine_track_valid(track) || !kine_track_finite(speed)) return false;
    track->speed = speed;
    return true;
}

KINE_API bool Kine_Filament_AnimationTrackSetTimePosition(
    KineFilamentAnimationTrack *track, float timeSeconds) {
    if (!kine_track_valid(track) || !track->playing || !kine_track_finite(timeSeconds)) return false;
    const float length = track->animator->mesh->animations[(size_t)track->animationIndex].duration;
    track->position = std::clamp(timeSeconds, 0.0f, length);
    track->animator->poseDirty = true;
    return true;
}

KINE_API bool Kine_Filament_AnimationTrackSetLooped(KineFilamentAnimationTrack *track, bool looped) {
    if (!kine_track_valid(track)) return false;
    track->looped = looped;
    return true;
}

KINE_API bool Kine_Filament_AnimationTrackSetPriority(KineFilamentAnimationTrack *track, int priority) {
    if (!kine_track_valid(track) || priority < 0 || priority > 6) return false;
    track->priority = priority;
    track->animator->poseDirty = true;
    return true;
}

KINE_API bool Kine_Filament_AnimationTrackGetState(
    const KineFilamentAnimationTrack *track, KineAnimationTrackState *outState) {
    if (!kine_track_valid(track) || !outState) return false;
    *outState = {};
    outState->length = track->animator->mesh->animations[(size_t)track->animationIndex].duration;
    outState->timePosition = track->position;
    outState->speed = track->speed;
    outState->weightCurrent = track->weightCurrent;
    outState->weightTarget = track->weightTarget;
    outState->animationIndex = track->animationIndex;
    outState->priority = track->priority;
    outState->isPlaying = track->playing ? 1 : 0;
    outState->looped = track->looped ? 1 : 0;
    outState->active = (track->playing || track->stopping) ? 1 : 0;
    return true;
}

KINE_API bool Kine_Filament_AnimationTrackConsumeEvents(
    KineFilamentAnimationTrack *track, KineAnimationTrackEvents *outEvents) {
    if (!kine_track_valid(track) || !outEvents) return false;
    outEvents->stopped = track->stoppedEvents;
    outEvents->ended = track->endedEvents;
    outEvents->didLoop = track->loopEvents;
    track->stoppedEvents = track->endedEvents = track->loopEvents = 0;
    return true;
}

KINE_API bool Kine_Filament_AnimatorStep(KineFilamentAnimator *animator, float dt) {
    if (!animator || !animator->ctx || !animator->mesh || !kine_track_finite(dt) || dt < 0.0f)
        return false;
    bool changing = animator->poseDirty;
    for (auto *track : animator->tracks) {
        if (!track) continue;
        if (track->playing && track->speed != 0.0f && dt > 0.0f) changing = true;
        if (track->stopping || (track->fadeElapsed < track->fadeDuration && dt > 0.0f))
            changing = true;
        kine_track_advance(track, dt);
    }
    return !changing || kine_animator_apply_pose(animator);
}

KINE_API void Kine_Filament_StepAnimations(KineFilamentContext *ctx, float dt) {
    if (!ctx || !kine_track_finite(dt) || dt < 0.0f) return;
    for (auto *animator : ctx->animationAnimators)
        Kine_Filament_AnimatorStep(animator, dt);
}

KINE_API void Kine_Filament_SetAnimationAutoStep(KineFilamentContext *ctx, bool enabled) {
    if (ctx) ctx->animationAutoStep = enabled;
}

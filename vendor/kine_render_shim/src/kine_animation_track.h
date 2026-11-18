#ifndef KINE_ANIMATION_TRACK_H
#define KINE_ANIMATION_TRACK_H

#include <stdint.h>
#include <stdbool.h>

/* Include after kine_filament_shim.h; KINE_API, KineFilamentContext,
 * and KineFilamentMesh must already be declared. */
typedef struct KineFilamentAnimator KineFilamentAnimator;
typedef struct KineFilamentAnimationTrack KineFilamentAnimationTrack;

typedef struct KineAnimationTrackState {
    float length;
    float timePosition;
    float speed;
    float weightCurrent;
    float weightTarget;
    int32_t animationIndex;
    int32_t priority;    /* 0 Core, 1 Idle, 2 Movement, 3 Action, 4-6 Action2-4 */
    int32_t isPlaying;
    int32_t looped;
    int32_t active;      /* Also true while fading out after Stop() */
} KineAnimationTrackState;

typedef struct KineAnimationEvent {
    int32_t kind; /* 1: keyframe, 2: marker */
    float time;
    char name[128];
    char parameter[128];
} KineAnimationEvent;

typedef struct KineAnimationTrackEvents {
    int32_t stopped;
    int32_t ended;
    int32_t didLoop;
} KineAnimationTrackEvents;

#ifdef __cplusplus
extern "C" {
#endif

KINE_API KineFilamentAnimator *Kine_Filament_AnimatorCreate(KineFilamentContext *ctx, KineFilamentMesh *mesh);
KINE_API void Kine_Filament_AnimatorDestroy(KineFilamentAnimator *animator);
KINE_API KineFilamentAnimationTrack *Kine_Filament_AnimatorLoadAnimation(KineFilamentAnimator *animator, int animationIndex);
KINE_API int Kine_Filament_AnimatorGetTrackCount(const KineFilamentAnimator *animator);
KINE_API KineFilamentAnimationTrack *Kine_Filament_AnimatorGetTrack(KineFilamentAnimator *animator, int trackIndex);
KINE_API bool Kine_Filament_AnimatorStep(KineFilamentAnimator *animator, float dt);
KINE_API void Kine_Filament_StepAnimations(KineFilamentContext *ctx, float dt);
KINE_API void Kine_Filament_SetAnimationAutoStep(KineFilamentContext *ctx, bool enabled);

KINE_API int Kine_Filament_MeshCreateAnimation(KineFilamentMesh *mesh, const char *name, float duration);
/* Copies clips from source onto target, matching channels by bone name. Returns
 * the number of clips appended (0 when none could drive the target rig). */
KINE_API int Kine_Filament_MeshImportAnimations(KineFilamentMesh *target, KineFilamentMesh *source);
/* local CFrame offset from bind pose: x,y,z,r00..r22 (12 floats) */
KINE_API bool Kine_Filament_MeshAddAnimationPose(KineFilamentMesh *mesh, int clipIndex,
    const char *boneName, float time, const float *cframe12, float weight);
KINE_API bool Kine_Filament_MeshAddAnimationEvent(KineFilamentMesh *mesh, int clipIndex,
    float time, const char *name, const char *parameter, bool marker);
KINE_API float Kine_Filament_MeshGetKeyframeTime(const KineFilamentMesh *mesh, int clipIndex, const char *name);
KINE_API bool Kine_Filament_AnimationTrackPopEvent(KineFilamentAnimationTrack *track, KineAnimationEvent *outEvent);

KINE_API void Kine_Filament_AnimationTrackDestroy(KineFilamentAnimationTrack *track);
KINE_API bool Kine_Filament_AnimationTrackPlay(KineFilamentAnimationTrack *track, float fadeTime, float weight, float speed);
KINE_API bool Kine_Filament_AnimationTrackStop(KineFilamentAnimationTrack *track, float fadeTime);
KINE_API bool Kine_Filament_AnimationTrackAdjustWeight(KineFilamentAnimationTrack *track, float weight, float fadeTime);
KINE_API bool Kine_Filament_AnimationTrackAdjustSpeed(KineFilamentAnimationTrack *track, float speed);
KINE_API bool Kine_Filament_AnimationTrackSetTimePosition(KineFilamentAnimationTrack *track, float timeSeconds);
KINE_API bool Kine_Filament_AnimationTrackSetLooped(KineFilamentAnimationTrack *track, bool looped);
KINE_API bool Kine_Filament_AnimationTrackSetPriority(KineFilamentAnimationTrack *track, int priority);
KINE_API bool Kine_Filament_AnimationTrackGetState(const KineFilamentAnimationTrack *track, KineAnimationTrackState *outState);
KINE_API bool Kine_Filament_AnimationTrackConsumeEvents(KineFilamentAnimationTrack *track, KineAnimationTrackEvents *outEvents);

#ifdef __cplusplus
}
#endif

#endif

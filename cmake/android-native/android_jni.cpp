#include <jni.h>

#define SDL_MAIN_HANDLED
#include <SDL3/SDL_main.h>

extern "C" int Kine_AndroidMain(int argc, char** argv);

extern "C" SDL_DECLSPEC int SDLCALL SDL_main(int argc, char** argv) {
    return Kine_AndroidMain(argc, argv);
}

namespace filament {
class VirtualMachineEnv {
public:
    static jint JNI_OnLoad(JavaVM* vm);
};
}

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    return filament::VirtualMachineEnv::JNI_OnLoad(vm);
}

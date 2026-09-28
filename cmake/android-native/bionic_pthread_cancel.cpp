// Android's bionic does not implement POSIX thread cancellation. The entire
// cancellation API -- pthread_cancel, pthread_setcancelstate and
// pthread_setcanceltype -- is absent from both libc.so and <pthread.h> at every
// API level, which is what made the libmain.so link step fail with:
//
//   ld.lld: error: undefined symbol: pthread_setcancelstate
//   >>> referenced by kinemium-thread
//   >>>   .../kinemium-thread.o:(thread::[thread_unix.odin]::_create.__unix_thread_entry_proc-0)
//
// Odin's core:thread calls pthread_setcancelstate(.ENABLE, nil) and
// pthread_setcanceltype(.ASYNCHRONOUS, nil) at the top of every thread's entry
// function, so the reference is present in any build that starts a thread, and
// android_jni links with -Wl,--no-undefined.
//
// These stubs report the truth rather than faking success: a bionic thread is
// not cancellable, so the only cancel state and cancel type that can be
// reported are the "off" ones. They must return 0 rather than an error because
// Odin asserts that return value is 0, so an error code would abort every
// thread on its first instruction.
//
// The one behaviour this gives up is Thread_Terminate, the only Odin API that
// calls pthread_cancel: it becomes a no-op that abandons the thread instead of
// stopping it. Thread_Destroy, the normal path, uses pthread_join and is
// unaffected.

#include <pthread.h>

extern "C" {

int pthread_setcancelstate(int state, int *oldstate) {
    (void)state;
    if (oldstate != nullptr) {
        // PTHREAD_CANCEL_DISABLE, the only state a bionic thread can be in.
        *oldstate = 0;
    }
    return 0;
}

int pthread_setcanceltype(int type, int *oldtype) {
    (void)type;
    if (oldtype != nullptr) {
        // PTHREAD_CANCELTYPE_DEFERRED, inert without cancellation support.
        *oldtype = 0;
    }
    return 0;
}

int pthread_cancel(pthread_t thread) {
    (void)thread;
    return 0;
}

} // extern "C"

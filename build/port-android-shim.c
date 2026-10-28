// Android/Bionic port shim: Bionic has no pthread_tryjoin_np (glibc
// extension). Emulate it with pthread_kill(tid, 0) probing + join.
//
// Semantics match glibc: return 0 and reap the thread when it has
// terminated, EBUSY while it is still running. Only joinable threads are
// used with this helper (see clipboard/host.zig tryJoinThread).
#include <errno.h>
#include <pthread.h>
#include <signal.h>

int pthread_tryjoin_np(pthread_t thread, void **retval) {
    int probe = pthread_kill(thread, 0);
    if (probe == 0) return EBUSY;
    if (probe != ESRCH) return probe;
    return pthread_join(thread, retval);
}

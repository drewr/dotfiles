// Spike 1: probe vfork/execve/fork/wait semantics on Unikraft (Datum Compute unikernel).
// Answers: can a process spawn another process and observe its exit status, and does
// fork() give true copy-on-write semantics or is it a vfork alias?
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <spawn.h>

extern char **environ;

static void banner(const char *s) { printf("[spike1] %s\n", s); fflush(stdout); }

// Case A: vfork + execve of a binary that definitely exists in the image.
static void case_a(void) {
    banner("case A: vfork + execve(/bin/spikeecho) + wait4");
    pid_t p = vfork();
    if (p < 0) { printf("[spike1] case A: vfork failed errno=%d\n", errno); return; }
    if (p == 0) {
        char *argv[] = { "/bin/spikeecho", "hello-from-child", NULL };
        char *envp[] = { "PATH=/bin", NULL };
        execve("/bin/spikeecho", argv, envp);
        _exit(errno ? errno : 127); // only reached if execve fails
    }
    int st = 0;
    pid_t r = wait4(p, &st, 0, NULL);
    if (r == p && WIFEXITED(st))
        printf("[spike1] case A OK: child exited %d (execve worked)\n", WEXITSTATUS(st));
    else
        printf("[spike1] case A FAIL: wait4=%d status=0x%x exit=%d\n",
               (int)r, st, WIFEXITED(st) ? WEXITSTATUS(st) : -1);
    fflush(stdout);
}

// Case B: vfork + _exit(code); parent must see the code.
static void case_b(void) {
    banner("case B: vfork + _exit(42) + wait4");
    pid_t p = vfork();
    if (p == 0) _exit(42);
    int st = 0;
    pid_t r = wait4(p, &st, 0, NULL);
    if (r == p && WIFEXITED(st) && WEXITSTATUS(st) == 42)
        printf("[spike1] case B OK: child returned 42\n");
    else
        printf("[spike1] case B FAIL: wait4=%d status=0x%x\n", (int)r, st);
    fflush(stdout);
}

// Case C: is fork() true COW fork, or a vfork alias?
// True fork: child writes to a local variable; parent must NOT see it.
// vfork alias: child runs in the parent's address space before exec; the write would corrupt the parent.
static void case_c(void) {
    banner("case C: fork() semantics check (is it true COW fork?)");
    volatile int shared = 111;
    pid_t p = fork();
    if (p < 0) {
        printf("[spike1] case C OK: fork() returned ENOSYS/errno=%d (no true fork)\n", errno);
        fflush(stdout);
        return;
    }
    if (p == 0) {
        shared = 222;      // child-only mutation
        _exit(0);          // do NOT touch stdio here (unsafe under vfork)
    }
    int st = 0;
    wait4(p, &st, 0, NULL);
    if (shared == 111)
        printf("[spike1] case C OK: TRUE COW fork (parent saw %d, child's write isolated)\n", shared);
    else
        printf("[spike1] case C IMPORTANT: fork() is a vfork ALIAS "
               "(parent saw %d after child wrote 222) -> shared address space\n", shared);
    fflush(stdout);
}

// Case D: posix_spawn, the portable path libuv/Node prefer where available.
static void case_d(void) {
    banner("case D: posix_spawn(/bin/spikeecho) + waitpid");
    pid_t p;
    char *argv[] = { "/bin/spikeecho", "hello-from-spawn", NULL };
    int rc = posix_spawn(&p, "/bin/spikeecho", NULL, NULL, argv, NULL);
    if (rc != 0) {
        printf("[spike1] case D FAIL: posix_spawn rc=%d (%s)\n", rc, strerror(rc));
        fflush(stdout);
        return;
    }
    int st = 0;
    waitpid(p, &st, 0);
    printf("[spike1] case D OK: posix_spawn child exited %d\n",
           WIFEXITED(st) ? WEXITSTATUS(st) : -1);
    fflush(stdout);
}

int main(void) {
    banner("starting spike 1: vfork/execve/fork probe");
    printf("[spike1] vforktest: pid=%d\n", (int)getpid());
    fflush(stdout);
    case_a();
    case_b();
    case_c();
    case_d();
    banner("RESULT: did cases A-D above pass?");
    return 0;
}

// Spike 2: can a single root process act as an init/supervisor on Unikraft?
// Tests the pattern sshd needs: spawn a long-lived child, keep it alive, reap it,
// and use the OS facilities an init relies on (/proc, signals, setsid).
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>

static volatile sig_atomic_t got_usr1 = 0;
static void on_usr1(int s) { (void)s; got_usr1 = 1; }

static void probe_procfs(void) {
    printf("[spike2] /proc exists? ");
    struct stat st;
    if (stat("/proc", &st) == 0 && S_ISDIR(st.st_mode)) {
        printf("yes\n");
        DIR *d = opendir("/proc");
        int n = 0; if (d) { struct dirent *e; while ((e = readdir(d))) n++; closedir(d); }
        printf("[spike2] /proc entries: %d\n", n);
        // /proc/self and /proc/<pid> are what supervisors read
        char buf[64]; ssize_t r;
        int fd = open("/proc/self/stat", O_RDONLY);
        if (fd >= 0) { r = read(fd, buf, sizeof(buf)-1); close(fd);
            printf("[spike2] /proc/self/stat read: %s\n", r > 0 ? "ok" : "empty"); }
        else printf("[spike2] /proc/self/stat open failed errno=%d\n", errno);
        fd = open("/proc/self/status", O_RDONLY);
        if (fd >= 0) { r = read(fd, buf, sizeof(buf)-1); close(fd);
            printf("[spike2] /proc/self/status read: %s\n", r > 0 ? "ok" : "empty"); }
        else printf("[spike2] /proc/self/status open failed errno=%d\n", errno);
    } else {
        printf("no\n");
    }
    fflush(stdout);
}

static void probe_signals(void) {
    printf("[spike2] signals: ");
    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_usr1;
    if (sigaction(SIGUSR1, &sa, NULL) != 0) { printf("sigaction failed errno=%d\n", errno); fflush(stdout); return; }
    if (kill(getpid(), SIGUSR1) != 0) { printf("kill failed errno=%d\n", errno); fflush(stdout); return; }
    printf("SIGUSR1 self-delivery %s\n", got_usr1 ? "OK" : "NOT delivered");
    fflush(stdout);
}

static void probe_setsid_pty(void) {
    printf("[spike2] setsid: ");
    pid_t s = setsid();
    printf("%s (returns %d)\n", s >= 0 ? "OK" : "failed", (int)s);
    printf("[spike2] openpty via /dev/ptmx: ");
    int fd = open("/dev/ptmx", O_RDWR);
    printf("%s\n", fd >= 0 ? "OK" : "unavailable");
    if (fd >= 0) close(fd);
    fflush(stdout);
}

// A long-lived child that prints periodically, so the parent can prove supervision
// (it must stay alive while the parent waits, and be reapable when it exits).
static void supervise_child(void) {
    printf("[spike2] spawning long-lived child\n"); fflush(stdout);
    pid_t p = fork();
    if (p < 0) { printf("[spike2] fork failed errno=%d\n", errno); return; }
    if (p == 0) {
        for (int i = 0; i < 3; i++) {
            printf("[spike2-child] tick %d pid=%d ppid=%d\n", i, (int)getpid(), (int)getppid());
            fflush(stdout);
            sleep(1);
        }
        _exit(5);
    }
    // Parent: wait for that child specifically, proving supervision + reaping.
    int st = 0;
    pid_t r = waitpid(p, &st, 0);
    printf("[spike2] supervisor reaped child %d status=%d exit=%d\n",
           (int)r, st, WIFEXITED(st) ? WEXITSTATUS(st) : -1);
    fflush(stdout);
}

int main(void) {
    printf("[spike2] init/supervisor probe: pid=%d ppid=%d\n", (int)getpid(), (int)getppid());
    fflush(stdout);
    probe_procfs();
    probe_signals();
    probe_setsid_pty();
    supervise_child();
    printf("[spike2] done\n");
    fflush(stdout);
    return 0;
}

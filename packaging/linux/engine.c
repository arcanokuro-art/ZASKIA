#define _GNU_SOURCE
#include <sys/prctl.h>
#include <signal.h>
#include <unistd.h>
#include <stdio.h>
#include <limits.h>
#include <string.h>

/* Keep the engine under the application's lifetime, including crashes. */
int main(int argc, char **argv) {
    (void)argc;
    pid_t parent = getppid();
    if (parent == 1 || prctl(PR_SET_PDEATHSIG, SIGTERM) == -1 || getppid() != parent) return 1;
    char path[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (n < 0) return 1;
    path[n] = '\0';
    char *slash = strrchr(path, '/');
    if (!slash || (size_t)(slash - path) + sizeof("/llama-server") > sizeof(path)) return 1;
    strcpy(slash, "/llama-server");
    argv[0] = path;
    execv(path, argv);
    perror("ZASKIA engine");
    return 1;
}

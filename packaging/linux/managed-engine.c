#define _GNU_SOURCE
#include <sys/prctl.h>
#include <signal.h>
#include <unistd.h>
#include <stdio.h>
/* Own a process group and die with the application, including crash exits. */
int main(int argc, char **argv) {
    if (argc < 2 || argv[1][0] != '/') return 2;
    pid_t parent = getppid();
    if (parent == 1 || setpgid(0, 0) == -1 || prctl(PR_SET_PDEATHSIG, SIGTERM) == -1 || getppid() != parent) return 1;
    execv(argv[1], argv + 1);
    perror("ZASKIA managed engine");
    return 1;
}

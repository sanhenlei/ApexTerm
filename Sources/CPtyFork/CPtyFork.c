#include "CPtyFork.h"

#include <signal.h>
#include <unistd.h>
#include <util.h>

pid_t cpty_fork_exec(int master_fd, int slave_fd, const char *cwd,
                     const char *path, char *const argv[], char *const envp[]) {
    pid_t pid = fork();
    if (pid != 0) {
        return pid;
    }

    // Child: only async-signal-safe operations until execve.
    close(master_fd);

    sigset_t empty;
    sigemptyset(&empty);
    sigprocmask(SIG_SETMASK, &empty, NULL);

    if (cwd != NULL && cwd[0] != '\0') {
        chdir(cwd);
    }

    if (login_tty(slave_fd) != 0) {
        _exit(126);
    }
    if (slave_fd > STDERR_FILENO) {
        close(slave_fd);
    }

    execve(path, argv, envp);
    _exit(127);
}

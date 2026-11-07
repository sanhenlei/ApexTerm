#ifndef CPTYFORK_H
#define CPTYFORK_H

#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Forks a child that acquires the PTY slave as its controlling terminal.
///
/// In the child (async-signal-safe calls only until execve):
///   1. closes the PTY master fd
///   2. resets the inherited signal mask
///   3. optionally chdir(cwd)
///   4. login_tty(slave_fd): setsid + TIOCSCTTY + dup2 onto stdin/stdout/stderr
///   5. execve(path, argv, envp)
///
/// The controlling terminal is what makes job control (Ctrl+C / SIGINT via the
/// line discipline) work for the spawned login shell — posix_spawn alone cannot
/// perform the child-side TIOCSCTTY, which is why Ctrl+C was dead.
///
/// Returns the child pid to the parent, or -1 on fork failure.
pid_t cpty_fork_exec(int master_fd, int slave_fd, const char *cwd,
                     const char *path, char *const argv[], char *const envp[]);

#ifdef __cplusplus
}
#endif

#endif /* CPTYFORK_H */

#define _POSIX_C_SOURCE 200809L

#include "GamaTUISignal.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static void arm_rescue(int input_fd, int output_fd) {
    struct termios original;
    memset(&original, 0, sizeof(original));
    int result = gama_tui_signal_arm(input_fd, output_fd, &original);
    if (result != 0) {
        _exit(100 + result % 100);
    }
}

static int wait_for_child(pid_t child, int *status, int timeout_millis) {
    struct timespec delay = {.tv_sec = 0, .tv_nsec = 10 * 1000 * 1000};
    int attempts = timeout_millis / 10;
    for (int attempt = 0; attempt < attempts; ++attempt) {
        pid_t waited = waitpid(child, status, WNOHANG);
        if (waited == child) {
            return 1;
        }
        if (waited < 0) {
            return 0;
        }
        nanosleep(&delay, NULL);
    }
    return 0;
}

static int preserves_ignored_host_disposition(void) {
    pid_t child = fork();
    if (child < 0) {
        perror("fork");
        return 0;
    }
    if (child == 0) {
        struct sigaction ignored;
        memset(&ignored, 0, sizeof(ignored));
        ignored.sa_handler = SIG_IGN;
        sigemptyset(&ignored.sa_mask);
        if (sigaction(SIGTERM, &ignored, NULL) != 0) {
            _exit(2);
        }
        int input_fd = open("/dev/null", O_RDONLY);
        int output_fd = open("/dev/null", O_WRONLY);
        if (input_fd < 0 || output_fd < 0) {
            _exit(3);
        }
        arm_rescue(input_fd, output_fd);
        raise(SIGTERM);
        _exit(0);
    }

    int status = 0;
    if (waitpid(child, &status, 0) != child) {
        return 0;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int fatal_signal_does_not_block_on_output(void) {
    pid_t child = fork();
    if (child < 0) {
        perror("fork");
        return 0;
    }
    if (child == 0) {
        int descriptors[2];
        if (pipe(descriptors) != 0) {
            _exit(4);
        }
        arm_rescue(descriptors[0], descriptors[1]);

        int flags = fcntl(descriptors[1], F_GETFL);
        if (flags < 0 || fcntl(descriptors[1], F_SETFL, flags | O_NONBLOCK) != 0) {
            _exit(5);
        }
        char payload[4096];
        memset(payload, 'x', sizeof(payload));
        while (write(descriptors[1], payload, sizeof(payload)) > 0) {}
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            _exit(6);
        }
        if (fcntl(descriptors[1], F_SETFL, flags & ~O_NONBLOCK) != 0) {
            _exit(7);
        }

        raise(SIGTERM);
        _exit(8);
    }

    int status = 0;
    if (!wait_for_child(child, &status, 2000)) {
        kill(child, SIGKILL);
        waitpid(child, &status, 0);
        return 0;
    }
    return WIFSIGNALED(status) && WTERMSIG(status) == SIGTERM;
}

int main(void) {
    int passed = 1;
    if (!preserves_ignored_host_disposition()) {
        fputs("error: terminating rescue replaced the host SIGTERM disposition\n", stderr);
        passed = 0;
    }
    if (!fatal_signal_does_not_block_on_output()) {
        fputs("error: terminating rescue blocked on a full output descriptor\n", stderr);
        passed = 0;
    }
    if (!passed) {
        return 1;
    }
    puts("OK — terminal rescue preserves host dispositions and cannot block on fatal output");
    return 0;
}

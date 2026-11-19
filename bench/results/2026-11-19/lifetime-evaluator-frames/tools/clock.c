#define _GNU_SOURCE
#include <linux/perf_event.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

// The compiler calls CLOCK_MONOTONIC at each phase boundary on both targets.
static const uint64_t events[] = {PERF_COUNT_HW_INSTRUCTIONS, PERF_COUNT_HW_CPU_CYCLES,
                                  PERF_COUNT_HW_BRANCH_MISSES, PERF_COUNT_HW_CACHE_MISSES};
enum { count = sizeof(events) / sizeof(*events) };
static int active, log_fd;
static _Thread_local int fds[count], ready;
struct sample { int64_t ns; uint64_t tid; uint64_t values[count]; };

__attribute__((constructor)) static void start(void) {
    const char *path = getenv("GOOSE_PHASE_LOG");
    if (!path) return;
    log_fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (log_fd < 0) _exit(5);
    active = 1;
}

static void thread_counters(void) {
    for (int i = 0; i < count; i++) {
        struct perf_event_attr a = {.type = PERF_TYPE_HARDWARE, .size = sizeof(a),
                                    .config = events[i], .pinned = 1, .exclude_kernel = 1, .exclude_hv = 1};
        fds[i] = syscall(SYS_perf_event_open, &a, 0, -1, -1, 0);
        if (fds[i] < 0) { perror("perf_event_open"); _exit(2); }
    }
    ready = 1;
}

int clock_gettime(clockid_t id, struct timespec *ts) {
    int rc = syscall(SYS_clock_gettime, id, ts);
    if (rc || !active || id != CLOCK_MONOTONIC) return rc;
    if (!ready) thread_counters();
    struct sample row;
    row.tid = syscall(SYS_gettid);
    row.ns = (int64_t)ts->tv_sec * 1000000000 + ts->tv_nsec;
    for (int i = 0; i < count; i++) {
        if (read(fds[i], &row.values[i], sizeof(uint64_t)) != sizeof(uint64_t)) _exit(4);
    }
    if (write(log_fd, &row, sizeof(row)) != sizeof(row)) _exit(6);
    return rc;
}

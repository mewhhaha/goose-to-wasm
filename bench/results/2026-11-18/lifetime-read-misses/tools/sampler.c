#define _GNU_SOURCE
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

/* The Linux timer and handler run on the single thread executing the guest.
   The hosted memory reservation exceeds the guest's declared maximum. */
static const volatile unsigned char * volatile marker;
static volatile sig_atomic_t bins[16];
static volatile sig_atomic_t overruns;
static timer_t timer_id;
static struct sigaction previous;
static int signal_id;

static void tick(int signum, siginfo_t *info, void *context) {
    (void)signum;
    (void)context;
    if (!marker) return;
    unsigned value = *marker;
    if (value > 14) value = 15;
    bins[value]++;
    overruns += info->si_overrun;
}

int start_sampler(const unsigned char *where, long period_ns) {
    if (marker || period_ns <= 0 || period_ns >= 1000000000) return -1;
    signal_id = SIGRTMIN + 7;
    for (int i = 0; i < 16; ++i) bins[i] = 0;
    overruns = 0;
    struct sigaction action = {0};
    action.sa_sigaction = tick;
    action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&action.sa_mask);
    if (sigaction(signal_id, &action, &previous)) return -1;
    struct sigevent event = {0};
    event.sigev_notify = SIGEV_THREAD_ID;
    event.sigev_signo = signal_id;
    event._sigev_un._tid = (pid_t)syscall(SYS_gettid);
    if (timer_create(CLOCK_THREAD_CPUTIME_ID, &event, &timer_id)) {
        sigaction(signal_id, &previous, NULL);
        return -1;
    }
    struct itimerspec interval = {0};
    interval.it_interval.tv_nsec = period_ns;
    interval.it_value = interval.it_interval;
    marker = where;
    if (timer_settime(timer_id, 0, &interval, NULL)) {
        marker = NULL;
        timer_delete(timer_id);
        sigaction(signal_id, &previous, NULL);
        return -1;
    }
    return 0;
}

int stop_sampler(int *out) {
    if (!marker) return -1;
    sigset_t mask, saved;
    sigemptyset(&mask);
    sigaddset(&mask, signal_id);
    if (sigprocmask(SIG_BLOCK, &mask, &saved)) abort();
    marker = NULL;
    if (timer_delete(timer_id)) abort();
    struct timespec zero = {0};
    while (sigtimedwait(&mask, NULL, &zero) >= 0) {}
    for (int i = 0; i < 16; ++i) out[i] = bins[i];
    out[16] = overruns;
    if (sigaction(signal_id, &previous, NULL) || sigprocmask(SIG_SETMASK, &saved, NULL)) abort();
    return 0;
}

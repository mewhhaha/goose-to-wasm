// LD_PRELOAD sampler: SIGPROF every 2 ms of process CPU time, records the
// interrupted PC (relative to the main executable's load base) and the
// return address chain's first frames via frame pointers when available.
// At exit writes PROF_OUT (default prof.out): one hex offset per sample.
#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <ucontext.h>
#include <link.h>
#include <unistd.h>
#include <fcntl.h>
#define MAXS (1 << 22)
static unsigned long *samples; static volatile long count; static unsigned long base, limit;
static int fd = -1; static unsigned long buf[1024]; static int nbuf;
static void handler(int sig, siginfo_t *si, void *ctx) {
    ucontext_t *uc = (ucontext_t *)ctx; unsigned long pc = uc->uc_mcontext.gregs[REG_RIP];
    unsigned long rbp = uc->uc_mcontext.gregs[REG_RBP], rsp = uc->uc_mcontext.gregs[REG_RSP];
    unsigned long c1 = 0, c2 = 0;
    // Frame-pointer chain: valid only when the binary keeps frame pointers.
    if (rbp > rsp && rbp < rsp + (64ul << 20) && (rbp & 7) == 0) {
        unsigned long *fp = (unsigned long *)rbp; c1 = fp[1];
        unsigned long up = fp[0];
        if (up > rbp && up < rbp + (64ul << 20) && (up & 7) == 0) c2 = ((unsigned long *)up)[1];
    }
    buf[nbuf++] = pc >= base && pc < limit ? pc - base : (unsigned long)-1;
    buf[nbuf++] = c1 >= base && c1 < limit ? c1 - base : (unsigned long)-1;
    buf[nbuf++] = c2 >= base && c2 < limit ? c2 - base : (unsigned long)-1;
    if (nbuf >= 1023) { if (write(fd, buf, nbuf * sizeof buf[0]) < 0) {} nbuf = 0; }
}
static int phdr_cb(struct dl_phdr_info *info, size_t size, void *data) {
    if (base == 0 && info->dlpi_name[0] == 0) {
        base = info->dlpi_addr;
        for (int i = 0; i < info->dlpi_phnum; i++) if (info->dlpi_phdr[i].p_type == PT_LOAD) { unsigned long end = base + info->dlpi_phdr[i].p_vaddr + info->dlpi_phdr[i].p_memsz; if (end > limit) limit = end; }
    }
    return 0;
}
static void done(void) {
    struct itimerval z = {{0, 0}, {0, 0}}; setitimer(ITIMER_PROF, &z, 0);
    if (nbuf) { if (write(fd, buf, nbuf * sizeof buf[0]) < 0) {} nbuf = 0; }
}
__attribute__((constructor)) static void init(void) {
    dl_iterate_phdr(phdr_cb, 0);
    const char *out = getenv("PROF_OUT"); if (!out) out = "prof.out";
    fd = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_sigaction = handler; sa.sa_flags = SA_SIGINFO | SA_RESTART; sigaction(SIGPROF, &sa, 0);
    struct itimerval it = {{0, 2000}, {0, 2000}}; setitimer(ITIMER_PROF, &it, 0);
    atexit(done);
}

/* Common runtime input and timed-region barriers for all C oracle targets. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static volatile int64_t benchmark_sink;

int64_t bench_input(void) {
    long long value;
    if (scanf("%lld", &value) != 1) {
        fputs("host input is not an i64\n", stderr);
        exit(2);
    }
    return (int64_t)value;
}

double bench_input_f64(void) {
    double value;
    if (scanf("%lf", &value) != 1) {
        fputs("host input is not an f64\n", stderr);
        exit(2);
    }
    return value;
}

int64_t bench_clock(void) {
    struct timespec stamp;
    if (clock_gettime(CLOCK_MONOTONIC, &stamp) != 0) {
        fputs("monotonic clock unavailable\n", stderr);
        exit(2);
    }
    return (int64_t)stamp.tv_sec * INT64_C(1000000000) + stamp.tv_nsec;
}

#if defined(__GNUC__) || defined(__clang__)
__attribute__((noinline))
#endif
int64_t bench_barrier(int64_t value) {
    benchmark_sink = value;
    return benchmark_sink;
}

void bench_sink(int64_t value) {
    benchmark_sink = value;
}

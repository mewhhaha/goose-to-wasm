/*
 * Mandelbrot: each pixel of an N x N grid maps onto a fixed viewport of the
 * complex plane and iterates z <- z^2 + c until |z| > 2 or max_iter is reached.
 *
 * The program prints two integers on stdout: the checksum (the sum of every
 * pixel's iteration count) and the wall-clock nanoseconds spent computing it.
 *
 * THE CHECKSUM IS THE HARNESS'S CORRECTNESS GATE. In strict floating-point mode
 * it must be bit-identical across every compiler, every language and both ISAs.
 * That only holds because the operations below are multiply, add, subtract and
 * compare, all correctly rounded by IEEE 754 -- and because every implementation
 * evaluates them in exactly this order. Do not "simplify" the arithmetic: any
 * reassociation, or an FMA contraction of `zr2 - zi2 + cr`, changes the last bit,
 * flips a boundary pixel from 999 to 1000 iterations, and breaks the invariant.
 * See METHODOLOGY.md#the-strict-mode-invariant.
 */

#include <inttypes.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/* The viewport. Part of the cross-implementation contract: changing any of
 * these constants changes the reference checksum. */
#define X_MIN (-2.0)
#define X_MAX (0.5)
#define Y_MIN (-1.25)
#define Y_MAX (1.25)

/* The unit of work is one row. With any realistic N there are far more rows
 * than threads, which is what the dynamic hand-out below needs: the load is
 * imbalanced by design (interior pixels run to max_iter, exterior ones exit
 * after a few iterations), so a static contiguous split would measure the split
 * rather than the backend. */
struct worker {
    uint32_t n;
    uint32_t max_iter;
    double dx;
    double dy;
    atomic_uint_least32_t *next_row;
    uint64_t sum;
};

static uint64_t row_iterations(uint32_t row, uint32_t n, uint32_t max_iter, double dx, double dy)
{
    const double ci = Y_MIN + ((double)row + 0.5) * dy;
    uint64_t sum = 0;

    for (uint32_t col = 0; col < n; ++col) {
        const double cr = X_MIN + ((double)col + 0.5) * dx;
        double zr = 0.0;
        double zi = 0.0;
        uint32_t iter = 0;

        while (iter < max_iter) {
            const double zr2 = zr * zr;
            const double zi2 = zi * zi;
            if (zr2 + zi2 > 4.0) {
                break;
            }
            zi = 2.0 * zr * zi + ci;
            zr = zr2 - zi2 + cr;
            ++iter;
        }
        sum += iter;
    }
    return sum;
}

static void *work(void *arg)
{
    struct worker *worker = arg;
    uint64_t sum = 0;

    for (;;) {
        /* Relaxed, and explicitly so. The cursor publishes no data: every worker
         * accumulates into a local and stores it once, and `pthread_join` is what
         * makes that store visible to `main`. Bare `atomic_fetch_add` would be
         * sequentially consistent -- `ldaddal` on aarch64, an acquire-release RMW
         * paying for an ordering nothing here depends on -- and would leave this row
         * spelling the hand-out differently from the C++, Rust and Zig ones, which
         * all say relaxed. Same row order (none is promised), same checksum. */
        const uint32_t row = atomic_fetch_add_explicit(worker->next_row, 1, memory_order_relaxed);
        if (row >= worker->n) {
            break;
        }
        sum += row_iterations(row, worker->n, worker->max_iter, worker->dx, worker->dy);
    }
    worker->sum = sum;
    return NULL;
}

static uint32_t parse_positive(const char *text, const char *name)
{
    char *end = NULL;
    const unsigned long value = strtoul(text, &end, 10);

    if (*text == '\0' || end == NULL || *end != '\0' || value == 0 || value > UINT32_MAX) {
        fprintf(stderr, "%s must be a positive integer, got `%s`\n", name, text);
        exit(2);
    }
    return (uint32_t)value;
}

int main(int argc, char **argv)
{
    if (argc != 4) {
        fprintf(stderr, "usage: %s <n> <max_iter> <threads>\n", argv[0]);
        return 2;
    }

    /* Never compile-time constants: a backend would fold the whole computation
     * away and the benchmark would measure nothing, very quickly. */
    const uint32_t n = parse_positive(argv[1], "n");
    const uint32_t max_iter = parse_positive(argv[2], "max_iter");
    const uint32_t threads = parse_positive(argv[3], "threads");

    pthread_t *ids = malloc((size_t)threads * sizeof *ids);
    struct worker *workers = malloc((size_t)threads * sizeof *workers);
    if (ids == NULL || workers == NULL) {
        fprintf(stderr, "out of memory\n");
        return 1;
    }

    atomic_uint_least32_t next_row = 0;
    const double dx = (X_MAX - X_MIN) / (double)n;
    const double dy = (Y_MAX - Y_MIN) / (double)n;

    /* Thread creation is inside the timer on purpose: spawning the pool is part
     * of what a parallel runtime costs, and the point is to compare runtimes. */
    struct timespec started;
    struct timespec finished;
    clock_gettime(CLOCK_MONOTONIC, &started);

    for (uint32_t i = 0; i < threads; ++i) {
        workers[i] = (struct worker){
            .n = n,
            .max_iter = max_iter,
            .dx = dx,
            .dy = dy,
            .next_row = &next_row,
            .sum = 0,
        };
        if (pthread_create(&ids[i], NULL, work, &workers[i]) != 0) {
            fprintf(stderr, "could not create thread %" PRIu32 "\n", i);
            return 1;
        }
    }
    for (uint32_t i = 0; i < threads; ++i) {
        pthread_join(ids[i], NULL);
    }
    clock_gettime(CLOCK_MONOTONIC, &finished);

    /* Summing 64-bit integers is associative, so the reduction order cannot
     * perturb the checksum however the threads happened to finish. */
    uint64_t checksum = 0;
    for (uint32_t i = 0; i < threads; ++i) {
        checksum += workers[i].sum;
    }

    const int64_t elapsed_ns = (int64_t)(finished.tv_sec - started.tv_sec) * 1000000000
        + (int64_t)(finished.tv_nsec - started.tv_nsec);

    free(workers);
    free(ids);

    /* Printing the checksum is what stops dead-code elimination from deleting
     * the loop above. */
    printf("%" PRIu64 " %" PRId64 "\n", checksum, elapsed_ns);
    return 0;
}

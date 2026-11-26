/* Native thread pool for deterministic parallel compiler stages.
   Built over the pinned Goose runtime thread API (gs_thread_start,
   gs_thread_wait, gs_hardware_threads) so native/runtime files stay untouched. */
#if GS_NEED_THREADS
#ifndef G_SHARED
#define G_SHARED static
#endif

#ifdef _WIN32
typedef SRWLOCK GPoolMutex;
typedef CONDITION_VARIABLE GPoolCond;
#define g_cp_mutex_init(m)     InitializeSRWLock(m)
#define g_cp_cond_init(c)      InitializeConditionVariable(c)
#define g_cp_mutex_lock(m)     AcquireSRWLockExclusive(m)
#define g_cp_mutex_unlock(m)   ReleaseSRWLockExclusive(m)
#define g_cp_cond_wait(c, m)   SleepConditionVariableSRW((c), (m), INFINITE, 0)
#define g_cp_cond_broadcast(c) WakeAllConditionVariable(c)
#else
typedef pthread_mutex_t GPoolMutex;
typedef pthread_cond_t GPoolCond;
#define g_cp_mutex_init(m)     pthread_mutex_init((m), NULL)
#define g_cp_cond_init(c)      pthread_cond_init((c), NULL)
#define g_cp_mutex_lock(m)     pthread_mutex_lock(m)
#define g_cp_mutex_unlock(m)   pthread_mutex_unlock(m)
#define g_cp_cond_wait(c, m)   pthread_cond_wait((c), (m))
#define g_cp_cond_broadcast(c) pthread_cond_broadcast(c)
#endif

#define G_CPOOL_MAX_WORKERS 31

typedef struct {
    GRef ctx;
    GSlice out;
} GPoolCall2;

typedef void (*GPoolRangeFn)(int64_t g_base, const void *pkt, int64_t begin, int64_t end);

typedef struct {
    GPoolMutex lock;
    GPoolCond work_cv;
    GPoolCond done_cv;
    GPoolMutex barrier_lock;
    GPoolCond barrier_cv;
    uint64_t barrier_gen;
    int64_t barrier_arrived;
    int initialized;
    int shutdown_registered;
    int stop;
    int in_flight;
    int spmd_mode;
    int64_t spmd_count;
    int64_t spmd_done;
    int64_t worker_regions;
    int64_t spawned;
    int64_t worker_ids[G_CPOOL_MAX_WORKERS];
    uint64_t generation;
    int64_t active;
    int64_t next_index;
    int64_t total;
    int64_t chunk_size;
    int64_t participants;
    int64_t max_workers;
    GPoolRangeFn fn;
    const void *pkt;
} GCompilerPool;

G_SHARED GCompilerPool g_cpool;

static int64_t g_cpool_default_jobs(void) {
    int64_t n = gs_hardware_threads();
    if (n < 1) n = 1;
    if (n > 8) n = 8;
    if (n > G_CPOOL_MAX_WORKERS + 1) n = G_CPOOL_MAX_WORKERS + 1;
    return n;
}

static void g_cpool_init(int64_t worker_regions) {
    if (g_cpool.initialized) return;
    g_cp_mutex_init(&g_cpool.lock);
    g_cp_cond_init(&g_cpool.work_cv);
    g_cp_cond_init(&g_cpool.done_cv);
    g_cp_mutex_init(&g_cpool.barrier_lock);
    g_cp_cond_init(&g_cpool.barrier_cv);
    g_cpool.worker_regions = worker_regions;
    g_cpool.initialized = 1;
}

static void g_cpool_barrier(void) {
    if (!g_cpool.initialized || !g_cpool.spmd_mode || g_cpool.spmd_count <= 1) return;
    g_cp_mutex_lock(&g_cpool.barrier_lock);
    uint64_t gen = g_cpool.barrier_gen;
    g_cpool.barrier_arrived++;
    if (g_cpool.barrier_arrived == g_cpool.spmd_count) {
        g_cpool.barrier_arrived = 0;
        g_cpool.barrier_gen = gen + 1;
        g_cp_cond_broadcast(&g_cpool.barrier_cv);
    } else {
        while (g_cpool.barrier_gen == gen) {
            g_cp_cond_wait(&g_cpool.barrier_cv, &g_cpool.barrier_lock);
        }
    }
    g_cp_mutex_unlock(&g_cpool.barrier_lock);
}

static void g_cpool_grow_array(GRef ref, int64_t width, int64_t new_len) {
    int64_t old_len = g_len(ref, 3, -1, 0);
    if (new_len <= old_len) return;
    g_reserve(ref, 3, -1, 0, width, new_len);
    g_set_len(ref, 3, -1, 0, new_len);
#if defined(_WIN32) || defined(GS_POSIX_COMMIT_ON_FAULT)
    GArray a;
    memcpy(&a, g_address(ref), sizeof a);
    if (a.data && a.data != &g_empty_byte && width > 0) {
        size_t old_bytes = (size_t)old_len * (size_t)width;
        size_t new_bytes = (size_t)new_len * (size_t)width;
        for (size_t off = old_bytes; off < new_bytes; off += 4096) a.data[off] = 0;
        if (new_bytes > old_bytes) a.data[new_bytes - 1] = 0;
    }
#endif
}

static int64_t g_cpool_take_chunk(int64_t *out_end) {
    int64_t begin = g_cpool.next_index;
    int64_t total = g_cpool.total;
    if (begin >= total) {
        *out_end = begin;
        return begin;
    }
    int64_t rem = total - begin;
    int64_t denom = g_cpool.participants * 2;
    int64_t step = denom > 0 ? rem / denom : 1;
    if (step < 1) step = 1;
    if (step > g_cpool.chunk_size) step = g_cpool.chunk_size;
    int64_t end = begin + step;
    if (end > total) end = total;
    g_cpool.next_index = end;
    *out_end = end;
    return begin;
}

static void g_cpool_worker_release(void) {
    g_transfer_drop();
    g_region_pool_release();
}

static void g_cpool_worker_entry(uint8_t *arg) {
    int64_t slot = 0;
    memcpy(&slot, arg, sizeof slot);
    g_stack_check_init();
    g_region_pool_begin(g_cpool.worker_regions);
    uint64_t seen_gen = 0;
    for (;;) {
        g_cp_mutex_lock(&g_cpool.lock);
        while (!g_cpool.stop &&
               (!g_cpool.in_flight || g_cpool.generation == seen_gen ||
                slot >= g_cpool.max_workers ||
                (!g_cpool.spmd_mode && g_cpool.next_index >= g_cpool.total))) {
            g_cp_cond_wait(&g_cpool.work_cv, &g_cpool.lock);
        }
        if (g_cpool.stop) {
            g_cp_mutex_unlock(&g_cpool.lock);
            break;
        }
        seen_gen = g_cpool.generation;
        GPoolRangeFn fn = g_cpool.fn;
        const void *pkt = g_cpool.pkt;
        int spmd = g_cpool.spmd_mode;
        int64_t spmd_count = g_cpool.spmd_count;
        g_cpool.active++;
        if (spmd) {
            g_cp_mutex_unlock(&g_cpool.lock);
            fn(0, pkt, slot + 1, spmd_count);
            g_cp_mutex_lock(&g_cpool.lock);
            g_cpool.active--;
            g_cpool.spmd_done++;
            if (g_cpool.spmd_done >= g_cpool.max_workers && g_cpool.active == 0) {
                g_cp_cond_broadcast(&g_cpool.done_cv);
            }
        } else {
            for (;;) {
                int64_t end = 0;
                int64_t begin = g_cpool_take_chunk(&end);
                if (begin >= end) break;
                g_cp_mutex_unlock(&g_cpool.lock);
                fn(0, pkt, begin, end);
                g_cp_mutex_lock(&g_cpool.lock);
            }
            g_cpool.active--;
            if (g_cpool.active == 0 && g_cpool.next_index >= g_cpool.total) {
                g_cp_cond_broadcast(&g_cpool.done_cv);
            }
        }
        g_cp_mutex_unlock(&g_cpool.lock);
    }
}

static void g_cpool_shutdown(void) {
    if (!g_cpool.initialized) return;
    int64_t ids[G_CPOOL_MAX_WORKERS];
    int64_t count = 0;
    g_cp_mutex_lock(&g_cpool.lock);
    count = g_cpool.spawned;
    if (count == 0) {
        g_cp_mutex_unlock(&g_cpool.lock);
        return;
    }
    for (int64_t i = 0; i < count; i++) ids[i] = g_cpool.worker_ids[i];
    g_cpool.stop = 1;
    g_cp_cond_broadcast(&g_cpool.work_cv);
    g_cp_mutex_unlock(&g_cpool.lock);
    for (int64_t i = 0; i < count; i++) {
        gs_thread_wait(ids[i], NULL, NULL, "<cpool>", 0);
    }
    g_cp_mutex_lock(&g_cpool.lock);
    g_cpool.spawned = 0;
    g_cpool.stop = 0;
    g_cp_mutex_unlock(&g_cpool.lock);
}

static void g_cpool_ensure_workers_locked(int64_t want_workers) {
    if (!g_cpool.shutdown_registered) {
        g_cpool.shutdown_registered = 1;
        atexit(g_cpool_shutdown);
    }
    while (g_cpool.spawned < want_workers) {
        int64_t slot = g_cpool.spawned;
        int64_t id = gs_thread_start(g_worker_run, g_cpool_worker_release,
                                     g_cpool_worker_entry, &slot, (int64_t)sizeof slot, 0);
        g_cpool.worker_ids[slot] = id;
        g_cpool.spawned++;
    }
}

static uint8_t g_cpool_run(int64_t jobs, int64_t total, int64_t main_base,
                           GPoolRangeFn fn, const void *pkt) {
    if (!g_cpool.initialized || jobs <= 1 || total <= 1 || g_cpool.in_flight) return 0;
    int64_t participants = jobs;
    if (participants > G_CPOOL_MAX_WORKERS + 1) participants = G_CPOOL_MAX_WORKERS + 1;
    if (participants > total) participants = total;
    if (participants <= 1) return 0;
    int64_t want_workers = participants - 1;

    g_cp_mutex_lock(&g_cpool.lock);
    if (g_cpool.in_flight || g_cpool.stop) {
        g_cp_mutex_unlock(&g_cpool.lock);
        return 0;
    }
    g_cpool_ensure_workers_locked(want_workers);
    g_cpool.spmd_mode = 0;
    g_cpool.spmd_count = 0;
    g_cpool.spmd_done = 0;
    g_cpool.in_flight = 1;
    g_cpool.fn = fn;
    g_cpool.pkt = pkt;
    g_cpool.next_index = 0;
    g_cpool.total = total;
    g_cpool.participants = participants;
    g_cpool.max_workers = want_workers;
    int64_t max_chunk = total / (participants * 4);
    if (max_chunk < 1) max_chunk = 1;
    if (max_chunk > 64) max_chunk = 64;
    g_cpool.chunk_size = max_chunk;
    g_cpool.generation++;
    g_cp_cond_broadcast(&g_cpool.work_cv);

    for (;;) {
        int64_t end = 0;
        int64_t begin = g_cpool_take_chunk(&end);
        if (begin >= end) break;
        g_cp_mutex_unlock(&g_cpool.lock);
        fn(main_base, pkt, begin, end);
        g_cp_mutex_lock(&g_cpool.lock);
    }
    while (g_cpool.active > 0) {
        g_cp_cond_wait(&g_cpool.done_cv, &g_cpool.lock);
    }
    g_cpool.in_flight = 0;
    g_cpool.fn = NULL;
    g_cpool.pkt = NULL;
    g_cpool.max_workers = 0;
    g_cp_mutex_unlock(&g_cpool.lock);
    return 1;
}

static uint8_t g_cpool_run_spmd(int64_t jobs, int64_t max_threads, int64_t main_base,
                                GPoolRangeFn fn, const void *pkt) {
    if (!g_cpool.initialized || jobs <= 1 || max_threads <= 1 || g_cpool.in_flight) return 0;
    int64_t participants = jobs;
    if (participants > G_CPOOL_MAX_WORKERS + 1) participants = G_CPOOL_MAX_WORKERS + 1;
    if (participants > max_threads) participants = max_threads;
    if (participants <= 1) return 0;
    int64_t want_workers = participants - 1;

    g_cp_mutex_lock(&g_cpool.lock);
    if (g_cpool.in_flight || g_cpool.stop) {
        g_cp_mutex_unlock(&g_cpool.lock);
        return 0;
    }
    g_cpool_ensure_workers_locked(want_workers);
    g_cpool.spmd_mode = 1;
    g_cpool.spmd_count = participants;
    g_cpool.spmd_done = 0;
    g_cpool.barrier_arrived = 0;
    g_cpool.in_flight = 1;
    g_cpool.fn = fn;
    g_cpool.pkt = pkt;
    g_cpool.next_index = 0;
    g_cpool.total = 1;
    g_cpool.participants = participants;
    g_cpool.max_workers = want_workers;
    g_cpool.generation++;
    g_cp_cond_broadcast(&g_cpool.work_cv);
    g_cp_mutex_unlock(&g_cpool.lock);

    fn(main_base, pkt, 0, participants);

    g_cp_mutex_lock(&g_cpool.lock);
    while (g_cpool.spmd_done < want_workers || g_cpool.active > 0) {
        g_cp_cond_wait(&g_cpool.done_cv, &g_cpool.lock);
    }
    g_cpool.in_flight = 0;
    g_cpool.spmd_mode = 0;
    g_cpool.spmd_count = 0;
    g_cpool.fn = NULL;
    g_cpool.pkt = NULL;
    g_cpool.max_workers = 0;
    g_cp_mutex_unlock(&g_cpool.lock);
    return 1;
}

#endif

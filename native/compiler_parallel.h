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
    int initialized;
    int shutdown_registered;
    int stop;
    int in_flight;
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
    if (n > G_CPOOL_MAX_WORKERS + 1) n = G_CPOOL_MAX_WORKERS + 1;
    return n;
}

static void g_cpool_init(int64_t worker_regions) {
    if (g_cpool.initialized) return;
    g_cp_mutex_init(&g_cpool.lock);
    g_cp_cond_init(&g_cpool.work_cv);
    g_cp_cond_init(&g_cpool.done_cv);
    g_cpool.worker_regions = worker_regions;
    g_cpool.initialized = 1;
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
                slot >= g_cpool.max_workers || g_cpool.next_index >= g_cpool.total)) {
            g_cp_cond_wait(&g_cpool.work_cv, &g_cpool.lock);
        }
        if (g_cpool.stop) {
            g_cp_mutex_unlock(&g_cpool.lock);
            break;
        }
        seen_gen = g_cpool.generation;
        GPoolRangeFn fn = g_cpool.fn;
        const void *pkt = g_cpool.pkt;
        g_cpool.active++;
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

#endif

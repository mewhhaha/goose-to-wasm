#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
typedef struct { const char *file; int line; } GLoc;
#include "../slice_pool.h"
#include <assert.h>

/* slice_pool.h's span tree against a list of free spans, as stdlib
   slice_pool.goose drives it: first fit from the lowest index, a free that
   merges with both neighbours, growth in place into the following span, and
   a span reaching the end serving a request past it. */
typedef struct { int64_t idx, cnt; } Span;
static Span model[100000];
static int64_t spans;

static int64_t model_place(int64_t len, int64_t cnt) {
    for (int64_t i = 0; i < spans; i++) {
        if (model[i].cnt < cnt) continue;
        int64_t idx = model[i].idx;
        model[i].idx += cnt; model[i].cnt -= cnt;
        if (!model[i].cnt) { memmove(model + i, model + i + 1, (size_t)(spans - i - 1) * sizeof *model); spans--; }
        return idx;
    }
    if (spans && model[spans - 1].idx + model[spans - 1].cnt == len) return model[--spans].idx;
    return len;
}

static void model_free(int64_t idx, int64_t cnt) {
    if (cnt <= 0) return;
    int64_t i = 0;
    while (i < spans && model[i].idx < idx) i++;
    memmove(model + i + 1, model + i, (size_t)(spans - i) * sizeof *model); spans++;
    model[i] = (Span){idx, cnt};
    if (i + 1 < spans && model[i].idx + model[i].cnt == model[i + 1].idx) {
        model[i].cnt += model[i + 1].cnt;
        memmove(model + i + 1, model + i + 2, (size_t)(spans - i - 2) * sizeof *model); spans--;
    }
    if (i > 0 && model[i - 1].idx + model[i - 1].cnt == model[i].idx) {
        model[i - 1].cnt += model[i].cnt;
        memmove(model + i, model + i + 1, (size_t)(spans - i - 1) * sizeof *model); spans--;
    }
}

static int64_t model_regrow(int64_t len, int64_t idx, int64_t ol, int64_t cnt) {
    int64_t end = idx + ol;
    for (int64_t i = 0; i < spans; i++) {
        if (model[i].idx != end) continue;
        if (model[i].cnt >= cnt - ol || end + model[i].cnt == len) {
            model[i].idx += cnt - ol; model[i].cnt -= cnt - ol;
            if (model[i].cnt <= 0) { memmove(model + i, model + i + 1, (size_t)(spans - i - 1) * sizeof *model); spans--; }
            return idx;
        }
        break;
    }
    model_free(idx, ol);
    return model_place(len, cnt);
}

typedef struct { int64_t root, height, chain; } Tree;
typedef struct { int64_t idx, cnt; } Run;
static Run live[100000];

int main(int argc, char **argv) {
    g_runtime_start(argc, argv, 4, 0);
    static const GLoc at = {"slice pool test", 1};
    GArray nodes = g_array(0); GRef ref = g_ref(&nodes);
    Tree tree = {0, 0, 0}; GRef head = g_ref(&tree);
    int64_t len = 0, count = 0, height = 0;
    uint64_t seed = 12345;
    for (int step = 0; step < 200000; step++) {
        seed = seed * 6364136223846793005u + 1442695040888963407u;
        uint64_t r = seed >> 33;
        int64_t op = (int64_t)(r % 8);
        if (count == 0 || op < 4) {
            int64_t cnt = 1 + (int64_t)((r >> 3) % (op == 0 ? 300 : 9));
            int64_t got = nodes.len ? g_slice_pool_place(ref, head, len, cnt, &at) : len;
            int64_t want = spans || nodes.len ? model_place(len, cnt) : len;
            assert(got == want);
            if (got + cnt > len) len = got + cnt;
            if (count < 100000) live[count++] = (Run){got, cnt};
        } else if (op < 7) {
            int64_t k = (int64_t)((r >> 3) % (uint64_t)count);
            g_slice_pool_free(ref, head, live[k].idx, live[k].cnt, &at); model_free(live[k].idx, live[k].cnt);
            live[k] = live[--count];
        } else {
            int64_t k = (int64_t)((r >> 3) % (uint64_t)count);
            int64_t cnt = live[k].cnt + 1 + (int64_t)((r >> 12) % 5);
            int64_t got = g_slice_pool_regrow(ref, head, len, live[k].idx, live[k].cnt, cnt, &at);
            int64_t want = model_regrow(len, live[k].idx, live[k].cnt, cnt);
            assert(got == want);
            if (got + cnt > len) len = got + cnt;
            live[k] = (Run){got, cnt};
        }
        if (tree.height > height) height = tree.height;
    }
    assert(height >= 2);
    /* Every element is live or in one free span, once. */
    while (count) { g_slice_pool_free(ref, head, live[count - 1].idx, live[count - 1].cnt, &at); model_free(live[count - 1].idx, live[count - 1].cnt); count--; }
    assert(spans == 1 && model[0].idx == 0 && model[0].cnt == len);
    assert(g_slice_pool_place(ref, head, len, len, &at) == 0);

    /* trim reads the pages of free spans back as zeros and keeps live bytes. */
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    GArray bytes = g_array(2); GRef items = g_ref(&bytes);
    int64_t total = (int64_t)(page * 6 + 100);
    g_reserve(items, 3, -1, 0, 1, total); g_set_len(items, 3, -1, 0, total);
    memset(bytes.data, 7, (size_t)total);
    GArray spare = g_array(1); Tree pool = {0, 0, 0};
    int64_t free_at = 50, free_count = (int64_t)(page * 4);
    g_slice_pool_free(g_ref(&spare), g_ref(&pool), free_at, free_count, &at);
    assert(g_slice_pool_trim(g_ref(&spare), g_ref(&pool), (GSlice){g_ref(bytes.data), total}, 1, &at) == 1);
    for (int64_t i = 0; i < total; i++) {
        uintptr_t address = (uintptr_t)bytes.data + (uintptr_t)i;
        int inside = i >= free_at && i < free_at + free_count;
        uintptr_t first = ((uintptr_t)bytes.data + (uintptr_t)free_at + page - 1) / page * page;
        uintptr_t last = ((uintptr_t)bytes.data + (uintptr_t)(free_at + free_count)) / page * page;
        int discarded = inside && address >= first && address < last;
        assert(bytes.data[i] == (discarded ? 0 : 7));
    }
    puts("native slice pool span tree ok");
    return 0;
}

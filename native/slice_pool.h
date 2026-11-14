/* std's slice_pool (stdlib/slice_pool_internal.goose) keeps the span tree of
   reusable[]'s freelist (runtime_impl.h's gs_spans_*) in nodes of its own and
   a `tree` header, both of which the program can write. These are the externs
   it declares, gs_slice_pool_place, _free, _regrow and _trim, ported from
   upstream src/runtime/runtime_os.h at 855f1037 (Apache-2.0, runtime/LICENSE)
   onto this backend's arrays: nodes is a reference to a node[>..] header,
   which grows as a push would (g_reserve, g_set_len), tree a reference to the
   header struct, and items the pool's array viewed as bytes. Emitted only for
   programs that call them, beside storage.h in every program unit, since the
   runtime body's span tree is private to it.

   Everything read from the tree is checked before it is used: a node number
   must be one of the nodes past node 0 (G_SPC_BADNUM), an entry count must fit
   the node it is read from as a leaf or inner node, a height must fit a path,
   and an entry moved into or out of a node must be one it has room for or
   holds. A node reached at two levels of a path, or one the chain hands out
   while it is in the tree, keeps every access inside the nodes: each count
   these write fits a leaf, and the counts that index an inner node's children
   are checked where they are read. Sums of stored indices and counts wrap. A
   check that fails aborts with "slice pool span tree is corrupt" at the GLoc
   the extern was passed, the program's call into slice_pool
   (mark_located_functions); a wrong tree that passes them hands out wrong
   spans, which slice_pool checks against its length. New nodes start zeroed,
   as a pushed `node { .. }` would. */
#include <sys/mman.h>
#define G_SPC_NODE 512
#define G_SPC_LEAF ((G_SPC_NODE - 16) / 16)
#define G_SPC_FAN ((G_SPC_NODE - 16) / 24)
#define G_SPC_DEPTH 24
#ifdef GS_SPAN_DEPTH
_Static_assert(G_SPC_NODE == GS_SPAN_NODE && G_SPC_DEPTH == GS_SPAN_DEPTH, "slice pool nodes match the runtime's span tree");
#endif
typedef struct { int64_t n, link, idx[G_SPC_LEAF], cnt[G_SPC_LEAF]; } GSpcLeaf;
typedef struct { int64_t n, link, key[G_SPC_FAN], max[G_SPC_FAN], child[G_SPC_FAN]; } GSpcInner;
typedef struct { int64_t root, height, chain; } GSpcHead;
/* The nodes array, shared by the paths of one operation: its header, its
   elements and their count. */
typedef struct { GRef ref; unsigned char *base; int64_t n; } GSpcNodes;
typedef struct {
    GSpcHead *hd;
    GSpcNodes *ns;
    const GLoc *at;    /* The call that a corrupt tree is reported at. */
    int64_t h, node[G_SPC_DEPTH], pos[G_SPC_DEPTH];
} GSpcPath;

#define G_SPC_LEAFAT(p, i) ((GSpcLeaf *)((p)->ns->base + (size_t)(i) * G_SPC_NODE))
#define G_SPC_INNERAT(p, i) ((GSpcInner *)((p)->ns->base + (size_t)(i) * G_SPC_NODE))
#define G_SPC_SUM(a, b) ((int64_t)((uint64_t)(a) + (uint64_t)(b)))
#define G_SPC_BADNUM(p, i) ((uint64_t)(i) - 1 >= (uint64_t)(p)->ns->n - 1)
#define G_SPC_BADIN(p, i) (G_SPC_BADNUM(p, i) || (uint64_t)G_SPC_INNERAT(p, i)->n - 1 >= G_SPC_FAN)
#define G_SPC_BADLEAF(p, i) (G_SPC_BADNUM(p, i) || (uint64_t)G_SPC_LEAFAT(p, i)->n > G_SPC_LEAF)
#define G_SPC_BADH(h) ((uint64_t)(h) >= G_SPC_DEPTH)

static GS_NORETURN void g_spc_corrupt(const GSpcPath *p) {
    g_panic_at("slice pool span tree is corrupt", p->at->file, p->at->line);
}

static void g_spc_start(GSpcPath *p, GSpcNodes *ns, GRef nodes, GRef tree, const GLoc *at) {
    GArray a;memcpy(&a,g_address(nodes),sizeof a);
    ns->ref = nodes; ns->base = a.data; ns->n = a.len;
    p->hd = (GSpcHead *)g_address(tree); p->ns = ns; p->at = at;
}

/* A zeroed node pushed onto nodes. */
static int64_t g_spc_push(GSpcNodes *ns) {
    int64_t i = ns->n;
    if (i == INT64_MAX) g_panic("array length overflow");
    g_reserve(ns->ref, 3, -1, 0, G_SPC_NODE, i + 1);
    GArray a;memcpy(&a,g_address(ns->ref),sizeof a);
    memset(a.data + (size_t)i * G_SPC_NODE, 0, G_SPC_NODE);
    g_set_len(ns->ref, 3, -1, 0, i + 1);
    ns->base = a.data; ns->n = i + 1;
    return i;
}

static int64_t g_spc_newnode(GSpcPath *p) {
    int64_t i = p->hd->chain;
    if (i) {
        if (G_SPC_BADNUM(p, i)) g_spc_corrupt(p);
        p->hd->chain = G_SPC_LEAFAT(p, i)->link;
        return i;
    }
    return g_spc_push(p->ns);
}

static void g_spc_dropnode(GSpcPath *p, int64_t i) {
    G_SPC_LEAFAT(p, i)->link = p->hd->chain;
    p->hd->chain = i;
}

static void g_spc_open(const GSpcPath *p, GSpcLeaf *lf, int64_t s) {
    int64_t j;
    if ((uint64_t)lf->n >= G_SPC_LEAF || (uint64_t)s > (uint64_t)lf->n) g_spc_corrupt(p);
    for (j = lf->n; j > s; j--) {
        lf->idx[j] = lf->idx[j - 1];
        lf->cnt[j] = lf->cnt[j - 1];
    }
    lf->n++;
}

static void g_spc_close(const GSpcPath *p, GSpcLeaf *lf, int64_t s) {
    int64_t j;
    if ((uint64_t)s >= (uint64_t)lf->n) g_spc_corrupt(p);
    lf->n--;
    for (j = s; j < lf->n; j++) {
        lf->idx[j] = lf->idx[j + 1];
        lf->cnt[j] = lf->cnt[j + 1];
    }
}

static void g_spc_openin(const GSpcPath *p, GSpcInner *in, int64_t s) {
    int64_t j;
    if ((uint64_t)in->n >= G_SPC_FAN || (uint64_t)s > (uint64_t)in->n) g_spc_corrupt(p);
    for (j = in->n; j > s; j--) {
        in->key[j] = in->key[j - 1];
        in->max[j] = in->max[j - 1];
        in->child[j] = in->child[j - 1];
    }
    in->n++;
}

static void g_spc_closein(const GSpcPath *p, GSpcInner *in, int64_t s) {
    int64_t j;
    if (in->n > G_SPC_FAN || (uint64_t)s >= (uint64_t)in->n) g_spc_corrupt(p);
    in->n--;
    for (j = s; j < in->n; j++) {
        in->key[j] = in->key[j + 1];
        in->max[j] = in->max[j + 1];
        in->child[j] = in->child[j + 1];
    }
}

/* The largest of the w counts at v, or `stop` as soon as one reaches it. */
static int64_t g_spc_most(const int64_t *v, int64_t w, int64_t stop) {
    int64_t m = 0, k;
    for (k = 0; k < w && m < stop; k++)
        if (v[k] > m) m = v[k];
    return m;
}

static int64_t g_spc_max(GSpcPath *p, int64_t i, int leaf, int64_t stop) {
    return leaf ? g_spc_most(G_SPC_LEAFAT(p, i)->cnt, G_SPC_LEAFAT(p, i)->n, stop)
                : g_spc_most(G_SPC_INNERAT(p, i)->max, G_SPC_INNERAT(p, i)->n, stop);
}

static int64_t g_spc_key(GSpcPath *p, int64_t i, int leaf) {
    return leaf ? G_SPC_LEAFAT(p, i)->idx[0] : G_SPC_INNERAT(p, i)->key[0];
}

static void g_spc_fix(GSpcPath *p, int64_t l, int64_t was, int64_t now) {
    for (; l > 0; l--) {
        GSpcInner *in = G_SPC_INNERAT(p, p->node[l - 1]);
        int64_t k = p->pos[l - 1], c = p->node[l], m = in->max[k];
        int leaf = l == p->h;
        int64_t key = g_spc_key(p, c, leaf);
        int64_t nm = now >= m ? now : was < m ? m : g_spc_max(p, c, leaf, was);
        if (in->key[k] == key && nm == m) return;
        in->key[k] = key;
        in->max[k] = nm;
        was = m;
        now = nm;
    }
}

static int64_t g_spc_find(GSpcPath *p, int64_t idx) {
    int64_t l, i = p->hd->root, k;
    GSpcLeaf *lf;
    p->h = p->hd->height;
    if (G_SPC_BADH(p->h)) g_spc_corrupt(p);
    for (l = 0; l < p->h; l++) {
        GSpcInner *in;
        if (G_SPC_BADIN(p, i)) g_spc_corrupt(p);
        in = G_SPC_INNERAT(p, i);
        for (k = 1; k < in->n && in->key[k] <= idx; k++) {}
        p->node[l] = i;
        p->pos[l] = k - 1;
        i = in->child[k - 1];
    }
    p->node[p->h] = i;
    if (G_SPC_BADLEAF(p, i)) g_spc_corrupt(p);
    lf = G_SPC_LEAFAT(p, i);
    for (k = 0; k < lf->n && lf->idx[k] <= idx; k++) {}
    p->pos[p->h] = k - 1;
    return k - 1;
}

static void g_spc_newroot(GSpcPath *p, int64_t a, int64_t b, int leaf) {
    int64_t r = g_spc_newnode(p);
    GSpcInner *rn = G_SPC_INNERAT(p, r);
    rn->n = 2;
    rn->key[0] = g_spc_key(p, a, leaf);
    rn->max[0] = g_spc_max(p, a, leaf, INT64_MAX);
    rn->child[0] = a;
    rn->key[1] = g_spc_key(p, b, leaf);
    rn->max[1] = g_spc_max(p, b, leaf, INT64_MAX);
    rn->child[1] = b;
    p->hd->root = r;
    p->hd->height++;
}

static void g_spc_addchild(GSpcPath *p, int64_t l, int64_t k, int64_t child, int leaf) {
    for (;;) {
        GSpcInner *in = G_SPC_INNERAT(p, p->node[l]), *o = in;
        int64_t key = g_spc_key(p, child, leaf), max = g_spc_max(p, child, leaf, INT64_MAX);
        int64_t s = k, nn = 0;
        if (in->n == G_SPC_FAN) {
            int64_t half = G_SPC_FAN / 2;
            GSpcInner *r;
            nn = g_spc_newnode(p);
            if (nn == p->node[l]) g_spc_corrupt(p);
            in = G_SPC_INNERAT(p, p->node[l]);
            o = in;
            r = G_SPC_INNERAT(p, nn);
            r->n = in->n - half;
            memcpy(r->key, in->key + half, (size_t)r->n * 8);
            memcpy(r->max, in->max + half, (size_t)r->n * 8);
            memcpy(r->child, in->child + half, (size_t)r->n * 8);
            in->n = half;
            if (k > half) {
                o = r;
                s = k - half;
            }
        }
        g_spc_openin(p, o, s);
        o->key[s] = key;
        o->max[s] = max;
        o->child[s] = child;
        if (!nn) {
            g_spc_fix(p, l, 0, max);
            return;
        }
        if (l == 0) {
            g_spc_newroot(p, p->node[0], nn, 0);
            return;
        }
        g_spc_fix(p, l, INT64_MAX, 0);
        child = nn;
        leaf = 0;
        k = p->pos[l - 1] + 1;
        l--;
    }
}

static void g_spc_insert(GSpcPath *p, int64_t k, int64_t idx, int64_t cnt) {
    GSpcLeaf *lf = G_SPC_LEAFAT(p, p->node[p->h]), *o = lf;
    int64_t s = k, nn = 0;
    if (lf->n == G_SPC_LEAF) {
        int64_t half = G_SPC_LEAF / 2;
        GSpcLeaf *r;
        nn = g_spc_newnode(p);
        if (nn == p->node[p->h]) g_spc_corrupt(p);
        lf = G_SPC_LEAFAT(p, p->node[p->h]);
        o = lf;
        r = G_SPC_LEAFAT(p, nn);
        r->n = lf->n - half;
        memcpy(r->idx, lf->idx + half, (size_t)r->n * 8);
        memcpy(r->cnt, lf->cnt + half, (size_t)r->n * 8);
        lf->n = half;
        if (k > half) {
            o = r;
            s = k - half;
        }
    }
    g_spc_open(p, o, s);
    o->idx[s] = idx;
    o->cnt[s] = cnt;
    if (!nn) {
        g_spc_fix(p, p->h, 0, cnt);
    } else if (p->h == 0) {
        g_spc_newroot(p, p->node[0], nn, 1);
    } else {
        g_spc_fix(p, p->h, INT64_MAX, 0);
        g_spc_addchild(p, p->h - 1, p->pos[p->h - 1] + 1, nn, 1);
    }
}

static void g_spc_delete(GSpcPath *p, int64_t k) {
    GSpcLeaf *lf = G_SPC_LEAFAT(p, p->node[p->h]);
    int64_t c = lf->cnt[k], l;
    g_spc_close(p, lf, k);
    if (lf->n > 0 || p->h == 0) {
        g_spc_fix(p, p->h, c, 0);
        return;
    }
    g_spc_dropnode(p, p->node[p->h]);
    for (l = p->h - 1;; l--) {
        GSpcInner *in = G_SPC_INNERAT(p, p->node[l]);
        int64_t e = p->pos[l], m = in->max[e];
        g_spc_closein(p, in, e);
        if (in->n > 0) {
            g_spc_fix(p, l, m, 0);
            break;
        }
        /* A root of one child, which the functions never leave. */
        if (l == 0) g_spc_corrupt(p);
        g_spc_dropnode(p, p->node[l]);
    }
    while (p->hd->height > 0) {
        int64_t r = p->hd->root;
        if (G_SPC_BADNUM(p, r)) g_spc_corrupt(p);
        if (G_SPC_INNERAT(p, r)->n != 1) break;
        p->hd->root = G_SPC_INNERAT(p, r)->child[0];
        p->hd->height--;
        g_spc_dropnode(p, r);
    }
}

static void g_spc_take(GSpcPath *p, int64_t k, int64_t cnt) {
    GSpcLeaf *lf = G_SPC_LEAFAT(p, p->node[p->h]);
    int64_t c = lf->cnt[k];
    if (c <= cnt) {
        g_spc_delete(p, k);
        return;
    }
    lf->idx[k] = G_SPC_SUM(lf->idx[k], cnt);
    lf->cnt[k] = c - cnt;
    g_spc_fix(p, p->h, c, c - cnt);
}

static int64_t g_slice_pool_place(GRef nodes, GRef tree, int64_t len, int64_t cnt, const GLoc *at) {
    GSpcPath p;
    GSpcNodes ns;
    int64_t l, i, k = 0, j, m, c, now, idx, before[G_SPC_DEPTH];
    GSpcLeaf *lf = NULL;
    g_spc_start(&p, &ns, nodes, tree, at);
    if (cnt == 0 || ns.n == 0) return len;
    p.h = p.hd->height;
    if (G_SPC_BADH(p.h)) g_spc_corrupt(&p);
    i = p.hd->root;
    for (l = 0; l < p.h; l++) {
        GSpcInner *in;
        if (G_SPC_BADIN(&p, i)) g_spc_corrupt(&p);
        in = G_SPC_INNERAT(&p, i);
        for (k = 0, m = 0; k < in->n && in->max[k] < cnt; k++)
            if (in->max[k] > m) m = in->max[k];
        if (k == in->n) break;
        p.node[l] = i;
        p.pos[l] = k;
        before[l] = m;
        i = in->child[k];
    }
    if (l == p.h) {
        if (G_SPC_BADLEAF(&p, i)) g_spc_corrupt(&p);
        lf = G_SPC_LEAFAT(&p, i);
        for (k = 0, m = 0; k < lf->n && lf->cnt[k] < cnt; k++)
            if (lf->cnt[k] > m) m = lf->cnt[k];
        before[l] = m;
    }
    if (l < p.h || k == lf->n) {
        for (l = 0, i = p.hd->root; l < p.h; l++) {
            GSpcInner *in;
            if (G_SPC_BADIN(&p, i)) g_spc_corrupt(&p);
            in = G_SPC_INNERAT(&p, i);
            p.node[l] = i;
            p.pos[l] = in->n - 1;
            i = in->child[in->n - 1];
        }
        p.node[p.h] = i;
        if (G_SPC_BADLEAF(&p, i)) g_spc_corrupt(&p);
        lf = G_SPC_LEAFAT(&p, i);
        k = lf->n - 1;
        if (k < 0 || G_SPC_SUM(lf->idx[k], lf->cnt[k]) != len) return len;
        idx = lf->idx[k];
        g_spc_take(&p, k, cnt);
        return idx;
    }
    p.node[p.h] = i;
    p.pos[p.h] = k;
    idx = lf->idx[k];
    c = lf->cnt[k];
    if (c > cnt) {
        lf->idx[k] = G_SPC_SUM(idx, cnt);
        lf->cnt[k] = now = c - cnt;
        j = k + 1;
    } else if (lf->n > 1 || p.h == 0) {
        g_spc_close(&p, lf, k);
        now = 0;
        j = k;
    } else {
        g_spc_delete(&p, k);
        return idx;
    }
    for (l = p.h; l > 0; l--) {
        GSpcInner *in = G_SPC_INNERAT(&p, p.node[l - 1]);
        int64_t e = p.pos[l - 1], mx = in->max[e], nm = mx;
        int64_t key = g_spc_key(&p, p.node[l], l == p.h);
        if (c == mx) {
            const int64_t *v = l == p.h ? lf->cnt : G_SPC_INNERAT(&p, p.node[l])->max;
            int64_t w = l == p.h ? lf->n : G_SPC_INNERAT(&p, p.node[l])->n;
            nm = before[l] > now ? before[l] : now;
            for (; j < w && nm < c; j++)
                if (v[j] > nm) nm = v[j];
        }
        if (in->key[e] == key && nm == mx) break;
        in->key[e] = key;
        in->max[e] = nm;
        c = mx;
        now = nm;
        j = e + 1;
    }
    return idx;
}

typedef struct {
    GSpcLeaf *lf, *nl;
    int64_t k, nk;
    GSpcPath *np;
} GSpcNear;

static void g_spc_near(GSpcPath *p, GSpcPath *q, int64_t idx, int64_t end, GSpcNear *s) {
    int64_t l;
    s->k = g_spc_find(p, idx);
    s->lf = G_SPC_LEAFAT(p, p->node[p->h]);
    s->nl = NULL;
    s->nk = -1;
    s->np = p;
    if (s->k + 1 < s->lf->n) {
        s->nl = s->lf;
        s->nk = s->k + 1;
        return;
    }
    for (l = p->h - 1; l >= 0 && p->pos[l] + 1 >= G_SPC_INNERAT(p, p->node[l])->n; l--) {}
    if (l < 0 || G_SPC_INNERAT(p, p->node[l])->key[p->pos[l] + 1] != end) return;
    q->hd = p->hd;
    q->ns = p->ns;
    q->at = p->at;
    q->h = p->h;
    memcpy(q->node, p->node, (size_t)(l + 1) * 8);
    memcpy(q->pos, p->pos, (size_t)(l + 1) * 8);
    for (q->pos[l]++; l < q->h; l++) {
        int64_t c = G_SPC_INNERAT(q, q->node[l])->child[q->pos[l]];
        if (l + 1 < q->h ? G_SPC_BADIN(q, c) : G_SPC_BADLEAF(q, c)) g_spc_corrupt(q);
        q->node[l + 1] = c;
        q->pos[l + 1] = 0;
    }
    s->np = q;
    s->nl = G_SPC_LEAFAT(q, q->node[q->h]);
    s->nk = 0;
}

static void g_spc_release(GSpcPath *p, GSpcNear *s, int64_t idx, int64_t cnt) {
    GSpcLeaf *lf = s->lf, *nl = s->nl;
    int64_t k = s->k, nk = s->nk;
    int prev = k >= 0 && G_SPC_SUM(lf->idx[k], lf->cnt[k]) == idx;
    int next = nl && idx + cnt == nl->idx[nk];
    if (prev) {
        int64_t c = lf->cnt[k], m = G_SPC_SUM(G_SPC_SUM(c, cnt), next ? nl->cnt[nk] : 0);
        lf->cnt[k] = m;
        if (next && nl == lf) g_spc_close(p, lf, nk);
        g_spc_fix(p, p->h, c, m);
        if (next && nl != lf) g_spc_delete(s->np, nk);
    } else if (next) {
        int64_t c = nl->cnt[nk];
        nl->idx[nk] = idx;
        nl->cnt[nk] = G_SPC_SUM(c, cnt);
        g_spc_fix(s->np, s->np->h, c, nl->cnt[nk]);
    } else {
        g_spc_insert(p, k + 1, idx, cnt);
    }
}

static void g_slice_pool_free(GRef nodes, GRef tree, int64_t idx, int64_t cnt, const GLoc *at) {
    GSpcPath p, q;
    GSpcNodes ns;
    GSpcNear s;
    if (cnt <= 0) return;
    g_spc_start(&p, &ns, nodes, tree, at);
    if (ns.n == 0) {
        /* Node 0 stays zero, the chain's end. */
        g_spc_push(&ns);
        p.hd->chain = 0;
        p.hd->height = 0;
        p.hd->root = g_spc_newnode(&p);
    }
    g_spc_near(&p, &q, idx, idx + cnt, &s);
    g_spc_release(&p, &s, idx, cnt);
}

static int64_t g_slice_pool_regrow(GRef nodes, GRef tree, int64_t len, int64_t idx, int64_t ol, int64_t cnt, const GLoc *at) {
    GSpcPath p, q;
    GSpcNodes ns;
    GSpcNear s;
    int64_t end = idx + ol;
    g_spc_start(&p, &ns, nodes, tree, at);
    if (ns.n == 0) {
        g_slice_pool_free(nodes, tree, idx, ol, at);
        return g_slice_pool_place(nodes, tree, len, cnt, at);
    }
    g_spc_near(&p, &q, idx, end, &s);
    if (s.nl && s.nl->idx[s.nk] == end &&
        (s.nl->cnt[s.nk] >= cnt - ol || G_SPC_SUM(end, s.nl->cnt[s.nk]) == len)) {
        g_spc_take(s.np, s.nk, cnt - ol);
        return idx;
    }
    g_spc_release(&p, &s, idx, ol);
    return g_slice_pool_place(nodes, tree, len, cnt, at);
}

/* Returns pages to the OS, which reads them back as zeros; 0 means it refused. */
static int g_spc_discard(uintptr_t start, size_t len) {
#if defined(__APPLE__)
    return mmap((void *)start, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) != MAP_FAILED;
#else
    return madvise((void *)start, len, MADV_DONTNEED) == 0;
#endif
}

/* slice_pool's trim: returns the complete pages inside every free span to the
   OS, which reads them back as zeros. `items` is the pool's array viewed as
   bytes and `elem` its element size, so the span (idx, cnt) covers bytes
   [idx * elem, (idx + cnt) * elem). Free spans never touch, since a free
   merges with its neighbours, so each span is whole: a page is kept only
   where it also holds a live element, at either end. The walk visits each
   node once, so a tree whose children lead back to nodes already seen is
   corrupt, as is a span outside the array; both abort before anything is
   discarded past them. Pages lie inside items, below its region's top.
   0 means an OS request failed. */
static uint8_t g_slice_pool_trim(GRef nodes, GRef tree, GSlice items, int64_t elem, const GLoc *at) {
    GSpcPath p;
    GSpcNodes ns;
    long size = sysconf(_SC_PAGESIZE);
    uintptr_t page = size > 0 ? (uintptr_t)size : 0, data;
    int64_t count, visits = 0, l = 0;
    int ok = 1;
    g_spc_start(&p, &ns, nodes, tree, at);
    if (ns.n == 0 || items.len <= 0 || elem <= 0 || page == 0) return 1;
    count = items.len / elem;
    data = (uintptr_t)g_address(items.base);
    p.h = p.hd->height;
    if (G_SPC_BADH(p.h)) g_spc_corrupt(&p);
    p.node[0] = p.hd->root;
    p.pos[0] = 0;
    if (p.h ? G_SPC_BADIN(&p, p.node[0]) : G_SPC_BADLEAF(&p, p.node[0])) g_spc_corrupt(&p);
    while (l >= 0) {
        if (l == p.h) {
            GSpcLeaf *lf = G_SPC_LEAFAT(&p, p.node[l]);
            if (++visits >= ns.n) g_spc_corrupt(&p);
            for (int64_t k = 0; k < lf->n; k++) {
                int64_t idx = lf->idx[k], cnt = lf->cnt[k];
                if (idx < 0 || cnt <= 0 || idx > count || cnt > count - idx) g_spc_corrupt(&p);
                uintptr_t lo = data + (uintptr_t)(idx * elem);
                uintptr_t hi = data + (uintptr_t)((idx + cnt) * elem);
                uintptr_t start = (lo + page - 1) / page * page;
                uintptr_t end = hi / page * page;
                if (start < end && !g_spc_discard(start, (size_t)(end - start))) ok = 0;
            }
            l--;
            continue;
        }
        GSpcInner *in = G_SPC_INNERAT(&p, p.node[l]);
        if (p.pos[l] == 0 && ++visits >= ns.n) g_spc_corrupt(&p);
        if (p.pos[l] >= in->n) {
            l--;
            continue;
        }
        int64_t c = in->child[p.pos[l]++];
        if (l + 1 < p.h ? G_SPC_BADIN(&p, c) : G_SPC_BADLEAF(&p, c)) g_spc_corrupt(&p);
        l++;
        p.node[l] = c;
        p.pos[l] = 0;
    }
    return (uint8_t)ok;
}

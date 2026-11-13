/* Generated worker thunks own their instance and native region pool. */
#if GS_NEED_THREADS
#ifndef G_SHARED
#define G_SHARED static
#endif

/* One queue node or wait message may be held while its image is decoded.
   Decoding calls no user code. Keep this in TLS, not on a C stack skipped
   by a contained worker's abort. Both runtime transfers are malloc'd. */
G_SHARED GS_TLS void *g_transfer_pending;

static void g_transfer_hold(void *pointer) {
    if(g_transfer_pending) gs_panic("nested native transfer");
    g_transfer_pending=pointer;
}

static void g_transfer_drop(void) {
    void *pointer=g_transfer_pending;
    g_transfer_pending=NULL;
    free(pointer);
}

/* Snapshot arguments in evaluation order into an ordinary temporary
   region. Its activation already restores it on nonlocal returns. */
static uint8_t *g_transfer_append(GArray *packet,int64_t bytes) {
    if(bytes<0 || packet->len<0 || bytes>INT64_MAX-8 || packet->len>INT64_MAX-8-bytes)
        g_panic("thread transfer size overflow");
    int64_t old=packet->len;
    int64_t end=old+8+bytes;
    g_reserve(g_ref(packet),3,-1,0,1,end);
    memcpy(packet->data+old,&bytes,8);
    g_set_len(g_ref(packet),3,-1,0,end);
    return packet->data+old+8;
}

static const uint8_t *g_transfer_next(const uint8_t **cursor,int64_t *bytes) {
    int64_t size;
    memcpy(&size,*cursor,8);
    if(size<0) gs_panic("invalid native transfer size");
    const uint8_t *image=*cursor+8;
    *cursor=image+size;
    if(bytes) *bytes=size;
    return image;
}

static void g_worker_run(void (*entry)(uint8_t *),uint8_t *args) {
    entry(args);
}

static void g_worker_release(void) {
    g_transfer_drop();
    free(gs_gl);
    gs_gl=NULL;
    g_region_pool_release();
    /* gs_thread_main releases OS regions and its argument packet next. */
}

static int64_t g_worker_start(void (*entry)(uint8_t *),const void *packet,
                              int64_t bytes,int contained) {
    return gs_thread_start(g_worker_run,g_worker_release,entry,packet,bytes,contained);
}

#endif

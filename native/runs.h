/* Auxiliary typed root for newly bounded variable-relative runs. GArray stays24. */
typedef struct { GArray header; uint8_t *end; } GRunRoot;
typedef const uint8_t *(*GRunSkip)(const uint8_t *,const uint8_t *);
_Static_assert(sizeof(GRunRoot)==32,"bounded run receiver frame");
static GRunRoot g_run_root(int64_t slot) {
    GArray header=g_array(slot);return (GRunRoot){header,header.data};
}
static void g_run_reset(GRunRoot *receiving) {
    if(!receiving || !receiving->header.region)g_panic("run has no receiving region");
    receiving->header.len=0;receiving->end=receiving->header.data;
    receiving->header.region->stack.top=receiving->end;
}
static void g_run_check(const GRunRoot *root,GRunSkip skip) {
    if(!root || !root->header.region || !root->header.region->base || root->header.len<0)g_panic("invalid run receiver capability");
    uintptr_t base=(uintptr_t)root->header.region->base,data=(uintptr_t)root->header.data,end=(uintptr_t)root->end;
    if(data<base || end<data || data-base>root->header.region->usable || end-base>root->header.region->usable)g_panic("run end outside receiving region");
    const uint8_t *at=root->header.data;
    for(int64_t i=0;i<root->header.len;i++)at=skip(at,root->end);
    if(at!=root->end)g_panic("run count and committed span disagree");
}
static GImage g_run_view(const GRunRoot *root,int64_t index,GRunSkip skip) {
    g_run_check(root,skip);
    if(index<0 || index>=root->header.len)g_panic("run index outside committed count");
    const uint8_t *at=root->header.data;
    for(int64_t i=0;i<index;i++)at=skip(at,root->end);
    return (GImage){(uint8_t*)at,(uint8_t*)skip(at,root->end),NULL};
}
/* A descriptor over the actual receiving region, never a second byte owner. */
static GImage g_run_begin(GRunRoot *receiving,GRunSkip skip) {
    g_run_check(receiving,skip);
    if(receiving->header.len==INT64_MAX)g_panic("run length overflow");
    if(receiving->header.region->stack.top!=receiving->end)g_panic("run append has an open writer");
    return (GImage){receiving->end,receiving->end,receiving->header.region};
}
static uint8_t *g_run_finish(GRunRoot *receiving,GImage completed,GRunSkip skip) {
    g_run_check(receiving,skip);
    if(completed.region!=receiving->header.region || completed.base!=receiving->end || completed.end!=completed.region->stack.top)g_panic("run element has no receiving authority");
    if(skip(completed.base,completed.end)!=completed.end)g_panic("completed run element has trailing bytes");
    if(receiving->header.len==INT64_MAX)g_panic("run length overflow");
    receiving->header.len++;receiving->end=completed.end;return completed.base;
}
/* Internal result adaptation may reuse a descriptor of the same receiver only. */
static void g_run_land(GRunRoot *receiving,const GRunRoot *completed,GRunSkip skip) {
    g_run_check(receiving,skip);g_run_check(completed,skip);
    if(receiving->header.region!=completed->header.region || receiving->header.data!=completed->header.data || receiving->header.len!=completed->header.len || receiving->end!=completed->end)g_panic("run result was not constructed at its receiver");
}

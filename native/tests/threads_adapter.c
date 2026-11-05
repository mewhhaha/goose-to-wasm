#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
static _Atomic int pending_frees, global_frees, pool_frees;
static _Thread_local void *pending_probe, *global_probe, *pool_probe;
static void checked_free(void *p) {
    if(p && p==pending_probe) { atomic_fetch_add(&pending_frees,1);pending_probe=NULL; }
    if(p && p==global_probe) { atomic_fetch_add(&global_frees,1);global_probe=NULL; }
    if(p && p==pool_probe) { atomic_fetch_add(&pool_frees,1);pool_probe=NULL; }
    free(p);
}
#define free checked_free
#define GS_NEED_THREADS 1
#define GS_STACK_RESERVE (256u << 10)
#define GS_STACK_GAP (64u << 10)
#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
static void check(int ok,const char *what) { if(!ok) {fprintf(stderr,"%s\n",what);exit(2);} }
typedef uintptr_t GRef;
typedef struct {uint8_t *data;int64_t len;int64_t cap;} GArray;
static GRef g_ref(void *p) {return (GRef)(uintptr_t)p;}
static void g_panic(const char *s) {gs_abort_msg((const uint8_t *)s,(int64_t)strlen(s),__FILE__,__LINE__);}
static void g_reserve(GRef p,int kind,int64_t fixed,int prefix,int64_t width,int64_t count) {
    (void)kind;(void)fixed;(void)prefix;(void)width;
    check(count<=((GArray *)(uintptr_t)p)->cap,"fixture packet capacity");
}
static void g_set_len(GRef p,int kind,int64_t fixed,int prefix,int64_t count) {
    (void)kind;(void)fixed;(void)prefix;((GArray *)(uintptr_t)p)->len=count;
}
static _Thread_local gs_stack *test_pool;
static void g_region_pool_begin(void) {
    test_pool=calloc(1,sizeof *test_pool);pool_probe=test_pool;gs_stack_init(test_pool);
    test_pool->top[0]=42;test_pool->top++;
}
static void g_region_pool_release(void) {free(test_pool);test_pool=NULL;}
#include "../threads.h"
static gs_queue queue=GS_QUEUE_INIT;
static void worker(uint8_t *packet) {
    g_region_pool_begin();gs_gl=calloc(1,17);global_probe=gs_gl;
    const uint8_t *cursor=packet;
    check(!memcmp(g_transfer_next(&cursor,NULL),"abc",3),"first frame");
    int64_t size=99;
    g_transfer_next(&cursor,&size);check(size==0,"zero-size frame");
    int64_t mode;
    memcpy(&mode,g_transfer_next(&cursor,&size),8);check(size==8,"unaligned frame");
    gs_qnode *node=gs_qget(&queue);g_transfer_hold(node);pending_probe=node;
    check(node->size==0,"zero queue node");
    if(mode==1) gs_abort_msg((const uint8_t *)"decode abort",12,__FILE__,__LINE__);
    if(mode==2) {
        g_transfer_drop();
        uint8_t *message=malloc(19);g_transfer_hold(message);pending_probe=message;
        gs_abort_msg((const uint8_t *)"append abort",12,__FILE__,__LINE__);
    }
    g_transfer_drop();
}
int main(int argc,char **argv) {
    gs_rt_start(argc,argv,GS_STACK_RESERVE,GS_STACK_GAP,GS_STACK_BUDGET,0,1);
    gs_qinit(&queue);
    uint8_t data[128];GArray packet={data,0,sizeof data};
    memcpy(g_transfer_append(&packet,3),"abc",3);g_transfer_append(&packet,0);
    uint8_t *mode_slot=g_transfer_append(&packet,8);
    check(packet.len==35,"packet exact byte count");
    for(int64_t mode=0;mode<3;mode++) {
        memcpy(mode_slot,&mode,8);check(gs_qput(&queue,data,0),"queue put");
        int64_t id=g_worker_start(worker,packet.data,packet.len,1);
        uint8_t *msg=NULL;int64_t len=0;
        check(gs_thread_wait(id,&msg,&len,__FILE__,__LINE__)==(mode==0),"contained result");
        if(mode) check(msg && len>=12,"abort message survives worker teardown");
        gs_free_msg(msg);
        check(atomic_load(&global_frees)==mode+1,"globals released exactly once");
        check(atomic_load(&pool_frees)==mode+1,"pool released exactly once");
    }
    check(atomic_load(&pending_frees)==4,"queue nodes and pending wait messages released");
    gs_release_regions();puts("native thread adapters ok");
}

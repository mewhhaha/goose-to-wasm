#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
#include "../pools.h"
#include <assert.h>

int main(int argc,char **argv) {
    g_runtime_start(argc,argv,4,0);
    GArray pool=g_array(0);GRef header=g_ref(&pool);g_pool_init(header,1,1);
    for(int64_t i=0;i<3;i++) {
        int64_t slot=g_pool_take(header,8);assert(slot==i);memcpy(g_address(g_moving(header,slot*8)),&i,8);g_pool_commit(header,slot);
    }
    g_pool_free(header,0,"pool test",1);g_pool_free(header,2,"pool test",1);
    assert(g_pool_take(header,8)==2);assert(g_pool_take(header,8)==0);assert(pool.len==3);
    g_pool_free(header,1,"pool test",1);
    uint8_t image[1024];g_pool_image_write(image,header);
    GArray copy=g_array(2);g_reserve(g_ref(&copy),3,-1,0,8,3);g_set_len(g_ref(&copy),3,-1,0,3);
    g_pool_image_read(g_ref(&copy),image,3,1);assert(g_pool_take(g_ref(&copy),8)==1);
    assert(g_pool_take(header,8)==1);
    g_pool_init(header,1,2);
    GSlice a=g_pool_slice_resize(header,(GSlice){0},5,8,"pool test",1);
    GSlice b=g_pool_slice_resize(header,(GSlice){0},5,8,"pool test",1);
    int64_t saved=42;memcpy(g_address(a.base),&saved,8);g_pool_slice_free(header,b,8,"pool test",1);
    GSlice grown=g_pool_slice_resize(header,a,10,8,"pool test",1);assert(grown.base==a.base);
    int64_t got=0;memcpy(&got,g_address(grown.base),8);assert(got==42);
    GSlice tail=g_pool_slice_resize(header,(GSlice){0},4,8,"pool test",1);
    g_pool_slice_free(header,grown,8,"pool test",1);
    GSlice reused=g_pool_slice_resize(header,(GSlice){0},3,8,"pool test",1);assert(reused.base==a.base);
    assert(tail.base!=reused.base);int64_t bytes=g_pool_image_size(header);uint8_t *large=malloc((size_t)bytes);assert(large);
    g_reserve(g_ref(&copy),3,-1,0,8,pool.len);g_set_len(g_ref(&copy),3,-1,0,pool.len);
    g_pool_image_write(large,header);g_pool_image_read(g_ref(&copy),large,3,2);free(large);
    GSlice next=g_pool_slice_resize(g_ref(&copy),(GSlice){0},2,8,"pool test",1);
    assert((next.base-(uintptr_t)copy.data)/8==6);
    for(int64_t i=0;i<500;i++) {
        GSlice pair=g_pool_slice_resize(header,(GSlice){0},2,8,"pool test",1);
        g_pool_slice_free(header,(GSlice){pair.base,1},8,"pool test",1);
    }
    bytes=g_pool_image_size(header);large=malloc((size_t)bytes);assert(large);
    g_reserve(g_ref(&copy),3,-1,0,8,pool.len);g_set_len(g_ref(&copy),3,-1,0,pool.len);
    g_pool_image_write(large,header);g_pool_image_read(g_ref(&copy),large,3,2);free(large);
    GSlice left=g_pool_slice_resize(header,(GSlice){0},1,8,"pool test",1);
    GSlice right=g_pool_slice_resize(g_ref(&copy),(GSlice){0},1,8,"pool test",1);
    assert(left.base-(uintptr_t)pool.data==right.base-(uintptr_t)copy.data);
    puts("native pools ok");return 0;
}

#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
#include "../pools.h"
#include <assert.h>

/* An empty array maps nothing until it needs bytes, and then behaves as one
   made in an already reserved region. */
static void push(GArray *array,int64_t value) { g_push(g_ref(array),3,-1,0,8,&value); }
static int64_t at(GArray *array,int64_t index) {
    int64_t value;memcpy(&value,g_address(g_element(g_ref(array),3,-1,0,8,index,0)),8);return value;
}
int main(int argc,char **argv) {
    g_runtime_start(argc,argv,6,0);
    assert(gs_nregions==0);

    GArray empty=g_array(0);GRef header=g_ref(&empty);GRegion *region=empty.region;
    assert(empty.data==&g_empty_byte && empty.len==0 && region==&g_regions[0] && !region->base && !region->stack.top);
    GSlice view=g_view(header,3,-1,0,8);
    assert(view.base==g_ref(&g_empty_byte) && view.len==0 && g_element(header,3,-1,0,8,0,1)==view.base);
    g_reserve(header,3,-1,0,8,0);g_set_len(header,3,-1,0,0);g_begin_builder(header);
    assert(empty.data==&g_empty_byte && !region->base && !region->stack.top && g_cap(header,3,-1)==0 && gs_nregions==0);

    /* Zero-width elements never need bytes. */
    GArray units=g_array(1);g_reserve(g_ref(&units),3,-1,0,0,5);g_set_len(g_ref(&units),3,-1,0,5);
    assert(units.len==5 && g_cap(g_ref(&units),3,-1)==5 && !units.region->base && !units.region->stack.top && gs_nregions==0);
    assert(g_element(g_ref(&units),3,-1,0,0,4,0)==g_ref(&g_empty_byte));

    /* A watermark taken before the first bytes restores to the region's base. */
    GWatermark marks[1];g_mark_regions(0,1,marks);
    push(&empty,42);push(&empty,43);
    assert(gs_nregions==1 && region->base && empty.data==region->base && empty.len==2 && at(&empty,1)==43);
    assert(region->stack.top==region->base+16 && region->high_water==16 && region->usable==gs_regions[0].usable);
    g_restore_regions(0,1,marks);
    assert(region->stack.top==region->base && region->capacity==0);
    GArray again=g_array(0);assert(again.data==region->base && gs_nregions==1);

    /* Headers that publish an array follow it into its region. */
    GArray source=g_array(2),target=source;GPublication link;g_map_header(&link,g_ref(&source),g_ref(&target));
    push(&source,7);
    assert(target.data==source.data && source.data==g_regions[2].base && target.len==1 && at(&target,0)==7);
    g_publication_top=link.parent;

    /* A result built in its destination's region is the destination's array. */
    GArray destination=g_array(3),result=g_array(3);
    push(&result,9);assert(destination.data==&g_empty_byte && result.data==g_regions[3].base);
    GArray resolved=destination;g_array_resolve(&resolved);assert(resolved.data==result.data);
    g_reserve(g_ref(&destination),3,-1,0,8,0);
    assert(destination.data==result.data && g_regions[3].stack.top==result.data+8 && gs_nregions==3);
    GArray late=g_array(3);push(&late,11);
    assert(late.data==result.data+8 && gs_nregions==3 && at(&result,0)==9);

    /* A pool sizes slices against its owner's reservation. */
    GArray pool=g_array(4);g_pool_init(g_ref(&pool),5,2);
    assert(pool.data==g_regions[4].base && gs_nregions==5);
    GSlice slice=g_pool_slice_resize(g_ref(&pool),(GSlice){0},3,8,"lazy test",1);
    assert(slice.len==3 && slice.base==g_ref(pool.data));

    /* Trimming skips slots nothing has reserved. */
    GArray idle=g_array(1);(void)idle;
    assert(gs_trim_memory() && at(&source,0)==7 && at(&result,0)==9 && at(&late,0)==11 && gs_nregions==5);
    puts("native lazy regions ok");return 0;
}

#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
#include "../images.h"
#include <assert.h>
#include <sys/wait.h>

static void rejected(GRegion *region,int operation) {
    pid_t child=fork();assert(child>=0);
    if(!child) {
        if(operation==0)g_image_space(region,-1);
        if(operation==1)g_image_space(region,INT64_MAX);
        if(operation==2)g_image_advance(region,region->base);
        if(operation==3)g_image_advance(region,(uint8_t*)((uintptr_t)region->base+region->usable+1));
        _exit(0);
    }
    int status;assert(waitpid(child,&status,0)==child);assert(WIFEXITED(status) && WEXITSTATUS(status)!=0);
}

int main(int argc,char **argv) {
    _Static_assert(sizeof(GImage)==24 && _Alignof(GImage)==1,"image controls can inhabit packed native frames");
    g_runtime_start(argc,argv,5,0);
    GImage image=g_image(0);uint8_t *cursor=g_image_space(image.region,10);
    cursor+=gs_zig_write(cursor,300);g_image_advance(image.region,cursor);
    cursor=g_image_space(image.region,7);cursor=g_image_count_write(cursor,4,3);
    memcpy(cursor,"abc",3);cursor+=3;g_image_finish(g_ref(&image),cursor);
    assert(g_image_span(image)==9 && gs_zig_read(image.base)==300);
    int64_t count=0;const uint8_t *text=g_image_count_read(image.base+2,4,&count);
    assert(count==3 && !memcmp(text,"abc",3) && text+count==image.end);
    GImage copy=g_image(1);g_image_copy_into(g_ref(&copy),image);
    assert(g_image_span(copy)==9 && copy.base!=image.base && !memcmp(copy.base,image.base,9));
    image.base[8]='d';assert(copy.base[8]=='c');
    GImage same={copy.base,copy.base+2,NULL};g_image_copy_into(g_ref(&copy),same);
    assert(copy.end==copy.base+2 && copy.region->stack.top==copy.base+9);
    GImage shorter={image.base,image.base+2,NULL};g_image_copy_into(g_ref(&copy),shorter);
    assert(copy.end==copy.base+2 && copy.region->stack.top==copy.end && copy.region->high_water==9);
    const int64_t values[]={63,-64,64,-65,8191,-8192,8192,INT64_MIN,INT64_MAX};
    GArray elements=g_array(2);
    for(int64_t i=0;i<9;i++) {
        cursor=g_image_space(elements.region,10);cursor+=gs_zig_write(cursor,values[i]);
        g_image_commit(g_ref(&elements),cursor,i+1);
    }
    assert(elements.len==9);
    const uint8_t *read=elements.data;
    for(int64_t i=0;i<elements.len;i++) {
        assert(gs_zig_read(read)==values[i]);read+=gs_uleb_size(read);
    }
    assert(read==elements.region->stack.top && read-elements.data==33);
    uint8_t *physical_end=elements.region->stack.top;
    g_image_commit(g_ref(&elements),physical_end,0);
    assert(elements.len==0 && elements.region->stack.top==physical_end);
    GWatermark mark;g_mark_regions(2,1,&mark);
    cursor=g_image_space(elements.region,10);cursor+=gs_zig_write(cursor,INT64_MAX);
    g_image_advance(elements.region,cursor);g_restore_regions(2,1,&mark);
    assert(elements.region->stack.top==physical_end && elements.region->high_water==43);
    for(int operation=0;operation<4;operation++)rejected(elements.region,operation);
    GImage limited=g_image(3);g_image_array_begin(g_ref(&limited),2,0,2,4,8);
    int64_t initial[2]={11,22};cursor=g_image_space(limited.region,16);memcpy(cursor,initial,16);
    g_image_advance(limited.region,cursor+16);g_image_array_finish(g_ref(&limited),2,4,8);
    assert(g_image_span(limited)==40 && g_len(g_ref(limited.base),2,-1,0)==2 && g_cap(g_ref(limited.base),2,-1)==4);
    int64_t spare;memcpy(&spare,limited.base+24,8);assert(spare==0);
    GImage incoming=g_image(4);g_image_array_begin(g_ref(&incoming),2,0,1,5,8);
    int64_t replacement=99;cursor=g_image_space(incoming.region,8);memcpy(cursor,&replacement,8);
    g_image_advance(incoming.region,cursor+8);g_image_array_finish(g_ref(&incoming),2,5,8);
    g_image_limited_assign(g_ref(limited.base),incoming,8);
    assert(g_cap(g_ref(limited.base),2,-1)==4 && g_len(g_ref(limited.base),2,-1,0)==1);
    memcpy(&spare,limited.base+16,8);assert(spare==22);
    memcpy(&replacement,g_address(g_element(g_ref(limited.base),2,-1,0,8,0,0)),8);assert(replacement==99);
    g_set_len(g_ref(incoming.base),2,-1,0,5);
    pid_t child=fork();assert(child>=0);
    if(!child){g_image_limited_assign(g_ref(limited.base),incoming,8);_exit(0);}
    int status;assert(waitpid(child,&status,0)==child);assert(WIFEXITED(status) && WEXITSTATUS(status)!=0);
    assert(g_cap(g_ref(limited.base),2,-1)==4 && g_len(g_ref(limited.base),2,-1,0)==1);
    g_image_zero(g_ref(&limited),8);
    assert(g_image_span(limited)==8 && g_cap(g_ref(limited.base),2,-1)==0 && g_len(g_ref(limited.base),2,-1,0)==0);
    unsigned char unaligned[sizeof(GArray)+1];memcpy(unaligned+1,&elements,sizeof elements);
    assert(g_array_region(g_ref(unaligned+1))==elements.region);
    assert(g_legacy_bytes==0);
    puts("native image storage ok");return 0;
}

#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
#include "../relative.h"
#include "../images.h"
#include "../runs.h"
#include <assert.h>
#include <stddef.h>
#include <sys/wait.h>

/* Independent Row: i64 id, signed self-relative u32 slot, u32 byte length. */
static const uint8_t *row_skip(const uint8_t *row,const uint8_t *end) {
    const uint8_t *cell=g_relative_cell_skip(row,end,8);
    g_relative_cell_skip(cell,end,4);
    if(g_relative_load(g_ref(cell),4,0,0)!=g_ref(row))g_panic("test Row self target mismatch");
    int64_t count;const uint8_t *text=g_image_count_check(cell+4,end,4,&count);
    if(!text || (uint64_t)count>(uintptr_t)end-(uintptr_t)text)g_panic("test Row text outside committed end");
    return text+count;
}
static void append(GRunRoot *root,int64_t id,const char *text,int64_t length) {
    int64_t old_count=root->header.len;uint8_t *old_end=root->end;
    GImage row=g_run_begin(root,row_skip);
    assert(row.base==old_end && row.end==old_end && row.region==root->header.region);
    uint8_t *at=g_image_space(row.region,16+length);
    memcpy(at,&id,8);g_relative_store(g_ref(at+8),g_ref(at),4,0,0,__FILE__,__LINE__);
    at=g_image_count_write(at+12,4,length);if(length)memcpy(at,text,(size_t)length);
    g_image_finish(g_ref(&row),at+length);
    /* Working bytes grant no logical read authority until complete publication. */
    assert(root->header.len==old_count && root->end==old_end);
    g_run_check(root,row_skip);
    assert(g_run_finish(root,row,row_skip)==old_end);
    assert(root->header.len==old_count+1 && root->end==row.end);
}
static void rejects(GRunRoot *root,int operation) {
    pid_t child=fork();assert(child>=0);
    if(!child) {
        GRunRoot wrong=*root;
        if(operation==0){wrong.end--;g_run_check(&wrong,row_skip);}
        if(operation==1){wrong.header.len++;g_run_check(&wrong,row_skip);}
        if(operation==2){memset(wrong.header.data+8,0,4);g_run_check(&wrong,row_skip);}
        if(operation==3){wrong.end=(uint8_t*)((uintptr_t)wrong.header.region->base+wrong.header.region->usable+1);g_run_check(&wrong,row_skip);}
        if(operation==4){g_image_advance(wrong.header.region,wrong.end+1);g_run_begin(&wrong,row_skip);}
        if(operation==5){GImage row=g_run_begin(root,row_skip);row.region=g_region(1);g_run_finish(root,row,row_skip);}
        if(operation==6){GImage row=g_run_begin(root,row_skip);row.base--;g_run_finish(root,row,row_skip);}
        if(operation==7){GImage row=g_run_begin(root,row_skip);row.end++;g_run_finish(root,row,row_skip);}
        if(operation==8){GRunRoot other=g_run_root(1);g_run_land(root,&other,row_skip);}
        if(operation==9){wrong.header.region=NULL;g_run_check(&wrong,row_skip);}
        _exit(0);
    }
    int status;assert(waitpid(child,&status,0)==child);
    assert(WIFEXITED(status) && WEXITSTATUS(status)!=0);
}
int main(int argc,char **argv) {
    _Static_assert(sizeof(GArray)==24 && sizeof(GRef)==8,"ordinary native ABI");
    _Static_assert(sizeof(GRunRoot)==32 && offsetof(GRunRoot,end)==24,"typed run end follows ordinary header");
    g_runtime_start(argc,argv,2,0);
    GRunRoot root=g_run_root(0);append(&root,1,"a",1);
    const uint8_t first[]={1,0,0,0,0,0,0,0,0xf8,0xff,0xff,0xff,1,0,0,0,'a'};
    assert(root.end-root.header.data==17 && !memcmp(root.header.data,first,sizeof first));
    GImage held=g_run_view(&root,0,row_skip);
    append(&root,2,"bc",2);
    const uint8_t second[]={2,0,0,0,0,0,0,0,0xf8,0xff,0xff,0xff,2,0,0,0,'b','c'};
    assert(root.end-root.header.data==35 && !memcmp(root.header.data+17,second,sizeof second));
    assert(held.base==root.header.data && held.end==root.header.data+17);
    assert(g_run_view(&root,1,row_skip).end==root.end);
    GRunRoot same=root;g_run_land(&root,&same,row_skip);
    for(int operation=0;operation<10;operation++)rejects(&root,operation);
    g_run_reset(&root);assert(root.header.len==0 && root.end==root.header.data && root.header.region->stack.top==root.end);
    append(&root,7,"",0);assert(root.header.len==1 && root.end-root.header.data==16);
    assert(root.header.data[0]==7 && root.header.data[12]==0);
    puts("native bounded run receivers ok");return 0;
}

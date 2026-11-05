#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
#include "../relative.h"
#include <assert.h>
#include <sys/wait.h>

static void rejected(GRef cell,GRef value,int width,int optional,GRef pool) {
    pid_t child=fork();assert(child>=0);
    if(!child){g_relative_store(cell,value,width,optional,pool,"relative test",1);_exit(0);}
    int status;assert(waitpid(child,&status,0)==child);assert(WIFEXITED(status) && WEXITSTATUS(status)!=0);
}
int main(int argc,char **argv) {
    g_runtime_start(argc,argv,0,0);
    struct __attribute__((packed)) cell_layout { int64_t value; uint16_t link; };
    _Static_assert(sizeof(struct cell_layout)==10,"packed relative record width");
    _Static_assert(sizeof(uint16_t[3])==6,"relative element stride");
    uint8_t bytes[32];memset(bytes,0xa5,sizeof bytes);GRef cell=g_ref(bytes+9);
    for(int width=1;width<=8;width*=2) {
        int bits=width*8;uint64_t maximum=INT64_MAX;
        if(width<8)maximum=(UINT64_C(1)<<(bits-1))-1;
        GRef up=cell+(uintptr_t)maximum;
        if(up>=cell){g_relative_store(cell,up,width,0,0,"relative test",1);assert(g_relative_load(cell,width,0,0)==up);}
        uint64_t minimum=UINT64_C(1)<<63;if(width<8)minimum=UINT64_C(1)<<(bits-1);
        GRef down=cell-(uintptr_t)minimum;
        if(down<=cell){g_relative_store(cell,down,width,0,0,"relative test",1);assert(g_relative_load(cell,width,0,0)==down);}
        g_relative_store(cell,0,width,1,0,"relative test",1);assert(!g_relative_load(cell,width,1,0));
        g_relative_store(cell,cell,width,0,0,"relative test",1);assert(g_relative_load(cell,width,0,0)==cell);
        rejected(cell,cell,width,1,0);
        if(width<8){rejected(cell,cell+(uintptr_t)maximum+1,width,0,0);rejected(cell,cell-(uintptr_t)minimum-1,width,0,0);}
        assert(bytes[8]==0xa5 && bytes[9+width]==0xa5);
        memset(bytes+9,0xa5,8);
    }
    uint64_t negative=UINT64_C(1)<<63;memcpy(g_address(cell),&negative,8);
    assert(g_relative_load(cell,8,0,0)==cell+(uintptr_t)negative);
    GRef pool=cell-1;
    for(int width=1;width<=4;width*=2) {
        uint64_t maximum=(UINT64_C(1)<<(width*8))-1;
        g_relative_store(cell,pool+(uintptr_t)maximum,width,1,pool,"relative test",1);
        assert(g_relative_load(cell,width,1,pool)==pool+(uintptr_t)maximum);
        rejected(cell,pool+(uintptr_t)maximum+1,width,1,pool);
        g_relative_store(cell,pool+1,width,1,pool,"relative test",1);assert(g_relative_load(cell,width,1,pool)==pool+1);
    }
    puts("native relative cells ok");return 0;
}

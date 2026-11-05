#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
#include "../relative.h"
#include <assert.h>
#include <sys/wait.h>

static void encoded(uint8_t *cell,uint8_t *end,GRef target,int optional,GRef pool,const uint8_t *expected,size_t size) {
    memset(cell,0xa5,(size_t)(end-cell));
    uint8_t *next=g_relative_var_store(g_ref(cell),end,target,optional,pool,__FILE__,__LINE__);
    assert(next==cell+size && !memcmp(cell,expected,size));
    assert(*next==0xa5);
    const uint8_t *after=NULL;
    assert(g_relative_var_load(g_ref(cell),next,optional,pool,&after)==target && after==next);
    assert(g_relative_var_skip(cell,next)==next);
}

static void rejected(int operation) {
    pid_t child=fork();assert(child>=0);
    if(!child) {
        uint8_t data[32]={0};GRef cell=g_ref(data);
        if(operation==0)g_relative_var_store(cell,data+32,cell,1,0,__FILE__,__LINE__);
        if(operation==1)g_relative_var_store(cell,data+1,129,0,1,__FILE__,__LINE__);
        if(operation==2)g_relative_var_store(cell,data+32,UINTPTR_MAX,0,0,__FILE__,__LINE__);
        if(operation==3)g_relative_var_store(cell,data+32,1,0,2,__FILE__,__LINE__);
        if(operation==4){data[0]=0x80;g_relative_var_skip(data,data+1);}
        if(operation==5){data[0]=0x80;g_relative_var_skip(data,data+2);}
        if(operation==6){memset(data,0xff,9);data[9]=2;g_relative_var_skip(data,data+10);}
        if(operation==7){memset(data,0x80,11);g_relative_var_skip(data,data+11);}
        if(operation==8){data[0]=20;g_relative_var_load(cell,data+1,0,UINTPTR_MAX-10,NULL);}
        if(operation==9){memset(data,0xff,9);data[9]=1;g_relative_var_load(cell,data+10,0,0,NULL);}
        if(operation==10){GVarRelative value={0};g_relative_load(g_ref(&value),0,1,0);}
        if(operation==11){GVarRelative value={0};value.extent=11;g_relative_load(g_ref(&value),0,1,0);}
        if(operation==12){GVarRelative value={0};value.extent=2;g_relative_load(g_ref(&value),0,1,0);}
        _exit(0);
    }
    int status;assert(waitpid(child,&status,0)==child);
    assert(WIFEXITED(status) && WEXITSTATUS(status)!=0);
}

int main(int argc,char **argv) {
    g_runtime_start(argc,argv,0,0);
    uint8_t arena[512]={0};uint8_t *cell=arena+128;
    const uint8_t zero[]={0},forward[]={0x80,1},backward[]={0x81,1},pool_byte[]={17};
    const uint8_t high[]={0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,1};
    encoded(cell,cell+16,g_ref(cell),0,0,zero,sizeof zero);
    encoded(cell,cell+16,0,1,0,zero,sizeof zero);
    encoded(cell,cell+16,g_ref(cell+64),0,0,forward,sizeof forward);
    encoded(cell,cell+16,g_ref(cell-65),0,0,backward,sizeof backward);
    encoded(cell,cell+16,g_ref(arena+16),0,g_ref(arena)-1,pool_byte,sizeof pool_byte);
    encoded(cell,cell+16,UINT64_C(0x8000000000000001),0,1,high,sizeof high);

    /* Independent one-way bytes: pool offsets use unsigned ULEB128. */
    const GRef values[]={1,127,128,257,0,16384};
    const uint8_t expected[]={1,127,0x80,1,0x81,2,0,0x80,0x80,1};
    uint8_t *cursor=arena;memset(arena,0xa5,64);
    for(size_t i=0;i<sizeof values/sizeof *values;i++) {
        GRef target=0;if(values[i])target=values[i]+1;
        cursor=g_relative_var_store(g_ref(cursor),arena+63,target,1,1,__FILE__,__LINE__);
    }
    assert(cursor==arena+sizeof expected && !memcmp(arena,expected,sizeof expected) && *cursor==0xa5);
    const uint8_t *read=arena;
    for(size_t i=0;i<sizeof values/sizeof *values;i++) {
        GRef target=0;if(values[i])target=values[i]+1;
        assert(g_relative_var_load(g_ref(read),cursor,1,1,&read)==target);
    }
    assert(read==cursor);

    /* Declaration control extent is separate from its natural pointer ABI. */
    GVarRelative slot={0};g_relative_store(g_ref(&slot),UINT64_C(0x8000000000000001),0,0,1,__FILE__,__LINE__);
    assert(slot.extent==10 && !memcmp(slot.bytes,high,10));
    assert(g_relative_load(g_ref(&slot),0,0,1)==UINT64_C(0x8000000000000001));
    g_relative_store(g_ref(&slot),0,0,1,0,__FILE__,__LINE__);
    assert(slot.extent==1 && !slot.bytes[0] && !g_relative_load(g_ref(&slot),0,1,0));
    _Static_assert(sizeof(GRef)==8,"natural reference remains a pointer");
    for(int operation=0;operation<13;operation++)rejected(operation);
    puts("bounded varint relative cells ok");
    return 0;
}

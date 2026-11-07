#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
#include "../relative.h"
#include <assert.h>
#include <sys/wait.h>

/* A proposed physical cursor is auxiliary authority, never a natural Ref. */
typedef struct { const uint8_t *at,*end; } CellCursor;
_Static_assert(sizeof(GRef)==8,"natural references stay eight bytes");
_Static_assert(sizeof(CellCursor)==16,"physical cursor carries an explicit bound");

static GRef read_cell(CellCursor *cursor,int optional,GRef pool) {
    const uint8_t *next=NULL;
    GRef value=g_relative_var_load(g_ref(cursor->at),cursor->end,optional,pool,&next);
    cursor->at=next;return value;
}
static void rejects(int operation) {
    pid_t child=fork();assert(child>=0);
    if(!child) {
        uint8_t bytes[]={0x80,0x01,0x5a};
        if(operation==0){CellCursor c={bytes,bytes+1};read_cell(&c,0,1);}
        if(operation==1)g_relative_var_store(g_ref(bytes),bytes+1,322,0,1,__FILE__,__LINE__);
        if(operation==3)g_relative_cell_skip(bytes,bytes+1,2);
        if(operation==4)g_relative_cell_skip(bytes,bytes+3,-1);
        if(operation==5)g_relative_cell_skip(bytes,bytes+1,0);
        if(operation==6)g_relative_cell_skip(bytes,bytes+3,INT64_C(4294967296));
        if(operation==2)g_relative_var_store(g_ref(bytes),bytes+3,g_ref(bytes),1,0,__FILE__,__LINE__);
        _exit(0);
    }
    int status;assert(waitpid(child,&status,0)==child);
    assert(WIFEXITED(status) && WEXITSTATUS(status)!=0);
}
int main(int argc,char **argv) {
    g_runtime_start(argc,argv,0,0);
    /* Independent one-way canonical bytes: zigzag(-65), ULEB(321), sentinel. */
    const uint8_t expected[]={0x81,0x01,0xc1,0x02,0x5a};
    uint8_t image[32];memset(image,0xa5,sizeof image);
    uint8_t *at=image+gs_zig_write(image,-65);
    at=g_relative_var_store(g_ref(at),image+sizeof image,322,0,1,__FILE__,__LINE__);
    *at++=0x5a;assert(at==image+sizeof expected && !memcmp(image,expected,sizeof expected));
    assert(*at==0xa5); /* No GVarRelative extent/control bytes in this image. */
    assert(gs_zig_read(expected)==-65);
    CellCursor r={expected+2,expected+sizeof expected};
    assert(read_cell(&r,0,1)==322 && r.at==expected+4 && *r.at==0x5a);
    assert(g_relative_var_skip(expected+2,expected+sizeof expected)==r.at);

    /* A backward self offset is measured from the actual receiving cell. */
    uint8_t self_image[4]={7,0xa5,0x5a,0xa5};
    at=g_relative_var_store(g_ref(self_image+1),self_image+2,g_ref(self_image),0,0,__FILE__,__LINE__);
    assert(at==self_image+2 && self_image[1]==1 && self_image[2]==0x5a);
    CellCursor self={self_image+1,self_image+2};
    assert(read_cell(&self,0,0)==g_ref(self_image) && self.at==self_image+2);

    /* Optional null consumes one canonical byte and leaves the next field. */
    uint8_t absent[]={0,0x73};CellCursor empty={absent,absent+1};
    assert(read_cell(&empty,1,1)==0 && empty.at==absent+1 && *empty.at==0x73);
    assert(g_relative_cell_skip(expected+2,expected+sizeof expected,0)==expected+4);
    assert(g_relative_cell_skip(expected+2,expected+4,2)==expected+4);
    for(int i=0;i<7;i++)rejects(i);
    puts("bounded physical relative cursor bytes ok");return 0;
}

#include "../runtime/runtime.h"
#include "../runtime/runtime_impl.h"
#include "../runtime/runtime_threads.h"
#include "../storage.h"
#include <assert.h>

static void recurse(int depth) {
    GActivation activation;GWatermark marks[1];g_activation_enter(&activation,0,0,marks);
    GFixed value __attribute__((cleanup(g_fixed_release)))=g_fixed_begin(1200000,1);
    assert(value.data[1199999]==0);value.data[1199999]=(unsigned char)depth;
    if(depth)recurse(depth-1);
    assert(value.data[1199999]==depth);g_activation_leave(&activation);
}
static void publish(void *target,const void *source) { memcpy(target,source,sizeof(int)); }
static void escape(void) {
    GActivation activation;GWatermark marks[1];g_activation_enter(&activation,0,0,marks);
    GFixed value __attribute__((cleanup(g_fixed_release)))=g_fixed_begin(1200000,1);
    value.data[1199999]=7;int result=value.data[1199999];g_throw(17,&result,sizeof result);
}
int main(int argc,char **argv) {
    g_runtime_start(argc,argv,0,0);
    GActivation activation;GWatermark marks[1];g_activation_enter(&activation,0,0,marks);
    unsigned char *first=NULL;
    for(int i=0;i<200;i++) {
        GFixed value __attribute__((cleanup(g_fixed_release)))=g_fixed_begin(1200000,1);
        if(!first)first=value.data;
        assert(first==value.data && value.data[1199999]==0);value.data[1199999]=1;
        recurse(8);assert(value.data[1199999]==1);
    }
    assert(g_fixed_region.stack.top==g_fixed_region.base);
    GReturnFrame frame={0};volatile int result=0;
    frame.function=17;frame.activation=&activation;frame.result=(void*)&result;frame.size=sizeof result;frame.publish=publish;g_return_top=&frame;
    if(!setjmp(frame.jump))escape();
    assert(result==7 && g_activation_top==&activation);
    g_return_top=NULL;g_activation_leave(&activation);
    assert(g_fixed_region.stack.top==g_fixed_region.base);
    puts("native fixed values ok");return 0;
}

#define _GNU_SOURCE 1
#include "runtime/runtime.h"
#include "runtime/runtime_impl.h"
#include "runtime/runtime_threads.h"
#include STORAGE_HEADER
#include <assert.h>
#include <sys/wait.h>

static __attribute__((noinline)) unsigned scalar_guard(unsigned n) {
    g_stack_check();return n+1;
}
static __attribute__((noinline)) void fill_bytes(volatile unsigned char *p,size_t n,unsigned value) {
    for(size_t i=0;i<n;i++)p[i]=(unsigned char)(value+i);
}
static __attribute__((noinline)) unsigned real_buffer(unsigned n) {
    unsigned char bytes[256];g_stack_check();fill_bytes(bytes,sizeof bytes,n);return bytes[n&255];
}
static __attribute__((noinline)) unsigned descend(unsigned depth,uintptr_t previous) {
    volatile unsigned char bytes[8192];g_stack_check();
    uintptr_t here=(uintptr_t)__builtin_stack_address();
    if(previous)assert(here<previous && previous-here>=sizeof bytes);
    fill_bytes(bytes,sizeof bytes,depth);
    unsigned value=bytes[depth&8191];
    if(depth)value+=descend(depth-1,here);
    return value+bytes[0];
}
static __attribute__((noinline)) void window(uintptr_t margin,int wrap) {
    uintptr_t here=(uintptr_t)__builtin_stack_address();
    if(wrap)g_native_stack_low=here+4096;
    else g_native_stack_low=here-margin;
    g_stack_check();
}
static void check_low(void) {
    pthread_attr_t a;void *base;size_t size;
    assert(!pthread_getattr_np(pthread_self(),&a));assert(!pthread_attr_getstack(&a,&base,&size));assert(!pthread_attr_destroy(&a));
    assert(g_native_stack_low==(uintptr_t)base);
    uintptr_t here=(uintptr_t)__builtin_stack_address();assert(here>=g_native_stack_low && here-g_native_stack_low<size);
}
static void *fresh_thread(void *unused) {
    (void)unused;assert(!g_native_stack_low);assert(scalar_guard(6)==7);check_low();
    uintptr_t first=g_native_stack_low;g_stack_check();assert(g_native_stack_low==first);
    g_native_stack_low=0;g_stack_check();assert(g_native_stack_low==first);
    assert(real_buffer(5)==10);assert(descend(4,0)==30);return NULL;
}
static void *overflow_thread(void *unused) { (void)unused;descend(200,0);return NULL; }
static void child_case(int kind) {
    if(kind==0)window(200000,0);
    if(kind==1)window(65536,0);
    if(kind==2)window(0,1);
    if(kind==3)window(131200,0);
    if(kind==4)window(131199,0);
    if(kind==5) {
        pthread_attr_t a;pthread_t t;assert(!pthread_attr_init(&a));assert(!pthread_attr_setstacksize(&a,262144));
        assert(!pthread_create(&t,&a,overflow_thread,NULL));assert(!pthread_attr_destroy(&a));assert(!pthread_join(t,NULL));
    }
}
static void expect_child(int kind,int should_panic) {
    int fds[2];assert(!pipe(fds));pid_t pid=fork();assert(pid>=0);
    if(!pid) { close(fds[0]);assert(dup2(fds[1],2)==2);close(fds[1]);child_case(kind);_exit(0); }
    close(fds[1]);char text[512];size_t n=0;
    while(n<sizeof text) { ssize_t got=read(fds[0],text+n,sizeof text-n);assert(got>=0);if(!got)break;n+=(size_t)got; }
    close(fds[0]);int status;assert(waitpid(pid,&status,0)==pid);assert(WIFEXITED(status));
    if(should_panic) {
        const char expected[]="goose runtime error: native call stack overflow (<native>:0)\n";
        assert(WEXITSTATUS(status)==1 && n==sizeof expected-1 && !memcmp(text,expected,n));
    } else assert(WEXITSTATUS(status)==0 && n==0);
}
int main(int argc,char **argv) {
#if EAGER_MAIN
    g_runtime_start(argc,argv,0,0);assert(g_native_stack_low);check_low();assert(scalar_guard(1)==2);check_low();
#else
    g_runtime_start(argc,argv,0,0);assert(!g_native_stack_low);assert(scalar_guard(1)==2);check_low();
#endif
    uintptr_t first=g_native_stack_low;g_stack_check();assert(g_native_stack_low==first);
    g_native_stack_low=0;g_stack_check();assert(g_native_stack_low==first);
    assert(real_buffer(7)==14);assert(descend(4,0)==30);
    for(int i=0;i<2;i++) { pthread_attr_t a;pthread_t t;assert(!pthread_attr_init(&a));assert(!pthread_attr_setstacksize(&a,524288+(size_t)i*262144));assert(!pthread_create(&t,&a,fresh_thread,NULL));assert(!pthread_attr_destroy(&a));assert(!pthread_join(t,NULL)); }
    assert(g_native_stack_low==first);
    expect_child(0,0);expect_child(1,1);expect_child(2,0);expect_child(5,1);
#if EXPECT_FAST
    expect_child(3,0);expect_child(4,1);
#endif
    puts("native stack position ok");return 0;
}

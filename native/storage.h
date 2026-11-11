/* Native frame adapters over the pinned plain-C Goose region runtime. */
#define _GNU_SOURCE 1
#include <stdint.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <setjmp.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
typedef uintptr_t GRef;
typedef struct GRegion { gs_stack stack; unsigned char *base; int64_t capacity, width; size_t usable; unsigned char *entry; uint64_t high_water; struct GRegion *freelist; int64_t free_count,free_mode; } GRegion;
typedef struct { unsigned char *top; int64_t capacity, width; unsigned char *entry; GRegion *freelist; int64_t free_count,free_mode; } GWatermark;
static GS_TLS GRegion *g_regions;
static GS_TLS int64_t g_region_count, g_region_peak;
static GS_TLS GRegion g_fixed_region;
typedef struct { unsigned char *data,*previous; } GFixed;

typedef struct { GRef base; int64_t len; } GSlice;
typedef struct { unsigned char *data; int64_t len; GRegion *region; } GArray;
typedef struct GClosure { void *function; int64_t count; GRef captures[]; } GClosure;
typedef struct GAllocation { struct GAllocation *next; void *data; } GAllocation;
static GS_TLS GAllocation *g_allocations;
static GS_TLS uint64_t g_legacy_bytes;
static int g_argc; static char **g_argv;
static GS_NORETURN void g_panic(const char *message) {
    gs_abort_msg((const uint8_t*)message,(int64_t)strlen(message),"<native>",0);
}
static GS_NORETURN void g_panic_at(const char *message,const char *file,int line) {
    gs_abort_msg((const uint8_t*)message,(int64_t)strlen(message),file,line);
}
static _Thread_local uintptr_t g_native_stack_low;
static GS_NOINLINE __attribute__((cold)) void g_stack_check_init(void) {
    pthread_attr_t attributes;void *base;size_t bytes;
    if(pthread_getattr_np(pthread_self(),&attributes)) gs_panic("cannot inspect native stack");
    int status=pthread_attr_getstack(&attributes,&base,&bytes);pthread_attr_destroy(&attributes);
    if(status) gs_panic("cannot inspect native stack");g_native_stack_low=(uintptr_t)base;
}
#if defined(__linux__) && defined(__x86_64__) && !defined(__TINYC__) && defined(__has_builtin)
#if __has_builtin(__builtin_stack_address)
#define GS_NATIVE_STACK_ADDRESS 1
#endif
#endif
static GS_INLINE void g_stack_check(void) {
    if(!g_native_stack_low)g_stack_check_init();
#ifdef GS_NATIVE_STACK_ADDRESS
    // Keep the SysV AMD64 red zone outside the 128 KiB safety reserve.
    uintptr_t here=(uintptr_t)__builtin_stack_address();
    if(here-g_native_stack_low<131072+128) g_panic("native call stack overflow");
#else
    unsigned char here;
    if((uintptr_t)&here-g_native_stack_low<131072) g_panic("native call stack overflow");
#endif
}
#undef GS_NATIVE_STACK_ADDRESS
static GS_NORETURN void g_index_fail(int64_t index,int64_t length,const char *file,int line) {
    if(!file)file="<native>";gs_idxfail(index,length,file,line);
}
static void *g_alloc(size_t n) {
    void *p=calloc(1,n+!n); if(!p) gs_panic("out of memory");
    GAllocation *a=malloc(sizeof *a); if(!a) gs_panic("out of memory");
    a->data=p; a->next=g_allocations; g_allocations=a;g_legacy_bytes+=n;return p;
}
static void g_region_pool_begin(int64_t regions) {
    g_region_count=regions;g_region_peak=0;g_legacy_bytes=0;g_fixed_region=(GRegion){0};
    g_regions=calloc((size_t)(regions+1),sizeof *g_regions);
    if(!g_regions)gs_panic("out of memory allocating native region plan");
}
static void g_region_pool_release(void) {
    while(g_allocations) {GAllocation *a=g_allocations;g_allocations=a->next;free(a->data);free(a);}
    free(g_regions);g_regions=NULL;g_region_count=0;g_region_peak=0;g_legacy_bytes=0;
}
#if GS_NEED_THREADS
static void g_transfer_drop(void);
#endif
static void g_region_stats(void) {
#if GS_STACK_STATS
    uint64_t live=0,high_water=0;
    int64_t stacks=gs_nstks;
    if(g_fixed_region.base)stacks++;
    for(int64_t i=0;i<g_region_count;i++) {
        GRegion *region=&g_regions[i];
        if(region->base)stacks++;
        if(region->base && region->stack.top)live+=(uint64_t)(region->stack.top-region->base);
        high_water+=region->high_water;
    }
    gs_stack_stats(stacks);
    fprintf(stderr,"native region stats: plan=%lld reserved=%ld peak_slot=%lld live_bytes=%llu sum_region_high_water_bytes=%llu legacy_bytes=%llu\n",
        (long long)g_region_count,gs_nregions,(long long)g_region_peak,(unsigned long long)live,
        (unsigned long long)high_water,(unsigned long long)g_legacy_bytes);
#endif
}
static GS_NORETURN void g_exit(int64_t code) {
    g_region_stats();gs_exit(code);
}
static void g_cleanup(void) {
    g_region_stats();
#if GS_NEED_THREADS
    g_transfer_drop();
#endif
    gs_release_regions();g_region_pool_release();
}
static void g_runtime_start(int argc,char **argv,int64_t regions,int64_t worker_regions) {
    // glibc reads the main stack's bounds from /proc/self/maps; read them before
    // any region mapping lengthens it.
    g_stack_check_init();
    g_argc=argc;g_argv=argv;g_region_count=regions;
    gs_rt_start(argc,argv,GS_STACK_RESERVE,GS_STACK_GAP,GS_STACK_BUDGET,regions+1,worker_regions+1);
    g_region_pool_begin(regions);
    atexit(g_cleanup);
}
static GRegion *g_region(int64_t slot) {
    if(slot<0 || slot>=g_region_count)g_panic("native region plan exhausted");
    GRegion *region=&g_regions[slot];
    if(!region->base) { gs_stack_init(&region->stack);region->base=region->stack.top;region->usable=gs_regions[gs_nregions-1].usable; }
    if(slot+1>g_region_peak)g_region_peak=slot+1;
    return region;
}
static unsigned char *g_fixed_alloc(size_t bytes) {
    GRegion *region=&g_fixed_region;
    if(!region->base) {
        gs_stack_init(&region->stack);region->base=region->stack.top;
        region->usable=gs_regions[gs_nregions-1].usable;
    }
    size_t offset=(size_t)(region->stack.top-region->base);
    if(offset>SIZE_MAX-15)g_panic("fixed value size overflow");
    offset=(offset+15)&~(size_t)15;
    if(bytes>region->usable || offset>region->usable-bytes)g_panic("fixed value region exhausted");
    unsigned char *data=region->base+offset;region->stack.top=data+bytes;
    uint64_t used=(uint64_t)(region->stack.top-region->base);
    if(used>region->high_water)region->high_water=used;
    return data;
}
static GFixed g_fixed_begin(size_t bytes,int zero) {
    unsigned char *previous=g_fixed_region.stack.top;
    unsigned char *data=g_fixed_alloc(bytes);
    if(zero && bytes)memset(data,0,bytes);
    return (GFixed){data,previous};
}
static void g_fixed_release(GFixed *value) {
    unsigned char *previous=value->previous;
    if(!previous)previous=g_fixed_region.base;
    if(g_fixed_region.stack.top>previous)g_fixed_region.stack.top=previous;
}
static GArray g_array(int64_t slot) {
    GRegion *region=g_region(slot);region->capacity=0;region->width=0;region->freelist=NULL;region->free_count=0;region->free_mode=0;
    region->entry=region->stack.top;GArray value={region->stack.top,0,region};return value;
}
static void g_mark_regions(int64_t base,int64_t count,GWatermark *marks) {
    if(base<0 || count<0 || base>g_region_count-count)g_panic("invalid native region watermark");
    for(int64_t i=0;i<count;i++) {
        GRegion *r=&g_regions[base+i];
        marks[i]=(GWatermark){r->stack.top,r->capacity,r->width,r->entry,r->freelist,r->free_count,r->free_mode};
    }
}
static void g_restore_regions(int64_t base,int64_t count,const GWatermark *marks) {
    for(int64_t i=0;i<count;i++) {
        GRegion *r=&g_regions[base+i];r->stack.top=marks[i].top;
        if(!r->stack.top)r->stack.top=r->base;
        r->capacity=marks[i].capacity;r->width=marks[i].width;r->entry=marks[i].entry;r->freelist=marks[i].freelist;r->free_count=marks[i].free_count;r->free_mode=marks[i].free_mode;
    }
}
typedef struct GPublication { struct GPublication *parent;uintptr_t source,target; } GPublication;
static _Thread_local GPublication *g_publication_top;
static void g_header_changed(uintptr_t address) {
    for(;;) {
        GPublication *link=g_publication_top;
        while(link && link->source!=address)link=link->parent;
        if(!link)return;
        memcpy((void *)link->target,(const void *)address,sizeof(GArray));address=link->target;
    }
}
static void g_map_header(GPublication *link,uintptr_t source,uintptr_t target) {
    if(source==target)return;
    *link=(GPublication){g_publication_top,source,target};g_publication_top=link;
}
static GRef g_ref(const void *p) { return (GRef)(uintptr_t)p; }
static unsigned char *g_address(GRef ref) { if(!ref)g_panic("null reference");return (unsigned char *)(uintptr_t)ref; }
static GRegion *g_array_region(GRef header) {
    GArray value;memcpy(&value,g_address(header),sizeof value);return value.region;
}
static GS_INLINE GRef g_offset(GRef ref,int64_t offset) {
    if(offset<0)g_panic("negative reference offset");
    if(!ref && offset)g_panic("null reference");
#if (defined(__GNUC__) || defined(__clang__)) && !defined(__TINYC__)
    unsigned char *base=(unsigned char *)(uintptr_t)ref;
    size_t bytes=__builtin_object_size(base,2);
    if(ref && bytes && (uint64_t)offset<=bytes)return g_ref(base+offset);
#endif
    return ref+(uintptr_t)offset;
}
static GRef g_owner(GRef root) { return root; }
static unsigned char g_empty_byte;
static GRef g_moving(GRef root,int64_t offset) {
    unsigned char *base;memcpy(&base,g_address(root),sizeof base);
    if(offset<0)g_panic("negative reference offset");if(!base && !offset)return g_ref(&g_empty_byte);return g_ref(base+offset);
}
static uint64_t g_read_length(const void *p,int n) { uint64_t v=0; memcpy(&v,p,n); return v; }
static void g_write_length(void *p,int n,uint64_t v) { memcpy(p,&v,n); }
static int64_t g_len(GRef r,int kind,int64_t fixed,int prefix) {
    if(kind==2 && fixed<0)return (int64_t)g_read_length(g_address(r)+4,4);
    if(kind==1) {
        uint64_t count;if(prefix)count=g_read_length(g_address(r),prefix);else count=gs_uleb_read(g_address(r));
        if(count>INT64_MAX)g_panic("array length exceeds native range");return (int64_t)count;
    }
    if(kind==5) { GSlice s; memcpy(&s,g_address(r),sizeof s); return s.len; }
    if(kind==0) return fixed;
    if(kind==2 && fixed>=0) return (int64_t)g_read_length(g_address(r),prefix);
    GArray a; memcpy(&a,g_address(r),sizeof a); return a.len;
}
static int64_t g_cap(GRef r,int kind,int64_t fixed) {
    if(kind==2 && fixed<0)return (int64_t)g_read_length(g_address(r),4);
    if(kind==0) return fixed;
    if(kind==2 && fixed>=0) return fixed;
    GArray a; memcpy(&a,g_address(r),sizeof a);if(!a.region)return 0;return a.region->capacity;
}
static GS_INLINE GRef g_element_at(GRef r,int kind,int64_t fixed,int prefix,int64_t width,int64_t index,int allow_end,const char *file,int line) {
    int64_t len=g_len(r,kind,fixed,prefix);
    if(index<0 || index>len || (!allow_end && index==len))g_index_fail(index,len,file,line);
    if(width && index>INT64_MAX/width) g_panic("array offset overflow");
    if(kind==1 || kind==2) {
        int64_t bytes=prefix;
        if(kind==1 && !bytes)bytes=gs_uleb_size(g_address(r));
        if(kind==2 && fixed<0)bytes=8;
        if(width && index>(INT64_MAX-bytes)/width)g_panic("array offset overflow");return g_offset(r,bytes+index*width);
    }
    if(kind==5) { GSlice s; memcpy(&s,g_address(r),sizeof s); return g_offset(s.base,index*width); }
    if(kind==0) return g_offset(r,index*width);
    return g_moving(r,index*width);
}
static GS_INLINE GRef g_element(GRef r,int kind,int64_t fixed,int prefix,int64_t width,int64_t index,int allow_end) {
    return g_element_at(r,kind,fixed,prefix,width,index,allow_end,NULL,0);
}
static GRef g_slot(GRef header,int kind,int64_t fixed,int prefix,int64_t width,int64_t index) {
    if(kind==2 && fixed<0)return g_offset(header,8+index*width);
    if(kind==0)return g_offset(header,index*width);
    if(kind==2 && fixed>=0)return g_offset(header,prefix+index*width);
    return g_moving(header,index*width);
}
static GSlice g_view(GRef r,int kind,int64_t fixed,int prefix,int64_t width) {
    GSlice s={g_element(r,kind,fixed,prefix,width,0,1),g_len(r,kind,fixed,prefix)}; return s;
}
static GS_INLINE void g_reserve(GRef r,int kind,int64_t fixed,int prefix,int64_t width,int64_t count) {
    if(count<0 || (width && count>INT64_MAX/width)) g_panic("invalid capacity");
    if(kind==2) { if(count>g_cap(r,kind,fixed)) g_panic("limited array capacity exceeded"); return; }
    if(kind!=3 && kind!=4) g_panic("array cannot grow");
    GArray a; memcpy(&a,g_address(r),sizeof a);
    if(!a.region)g_panic("array has no receiving region");
    uint64_t bytes=(uint64_t)count*(uint64_t)width;
    size_t offset=(size_t)(a.data-a.region->base);
    if(bytes>a.region->usable || offset>a.region->usable-bytes)g_panic("data stack overflow");
    if(count>a.region->capacity)a.region->capacity=count;
    a.region->width=width;
    a.region->stack.top=a.data+(size_t)a.region->capacity*(size_t)width;
    uint64_t used=(uint64_t)(a.region->stack.top-a.region->base);
    if(used>a.region->high_water)a.region->high_water=used;

}
static void g_set_len(GRef r,int kind,int64_t fixed,int prefix,int64_t count) {
    if(kind==2 && fixed<0){if(count<0 || count>g_cap(r,kind,fixed))g_panic("limited array capacity exceeded");g_write_length(g_address(r)+4,4,(uint64_t)count);}
    else if(kind==2 && fixed>=0) g_write_length(g_address(r),prefix,(uint64_t)count);
    else { GArray a; memcpy(&a,g_address(r),sizeof a); a.len=count;if(a.region && (kind==3 || kind==4))a.region->stack.top=a.data+(size_t)count*(size_t)a.region->width;memcpy(g_address(r),&a,sizeof a);g_header_changed(r); }
}
static void g_begin_builder(GRef ref) {
    GArray value;memcpy(&value,g_address(ref),sizeof value);value.len=0;
    if(value.region)value.region->stack.top=value.data;
    memcpy(g_address(ref),&value,sizeof value);
}
static GS_INLINE GRef g_push(GRef r,int kind,int64_t fixed,int prefix,int64_t width,const void *v) {
    int64_t n=g_len(r,kind,fixed,prefix);if(n==INT64_MAX)g_panic("array length overflow");g_reserve(r,kind,fixed,prefix,width,n+1);
    g_set_len(r,kind,fixed,prefix,n+1); GRef dst=g_element(r,kind,fixed,prefix,width,n,0);
    memcpy(g_address(dst),v,(size_t)width); return dst;
}
static void g_append_bytes(GRef r,int kind,int64_t fixed,int prefix,const void *data,int64_t count) {
    int64_t old=g_len(r,kind,fixed,prefix);
    if(count<0 || count>INT64_MAX-old)g_panic("array length overflow");
    if(kind==2 && count>g_cap(r,kind,fixed)-old)g_panic("limited array capacity exceeded");
    g_reserve(r,kind,fixed,prefix,1,old+count);
    if(count)memmove(g_address(g_element(r,kind,fixed,prefix,1,old,1)),data,(size_t)count);
    g_set_len(r,kind,fixed,prefix,old+count);
}
static void g_bytes(GArray *out,const void *p,int64_t n) {
    if(n<=0) return; GRef r=g_ref(out); g_reserve(r,3,-1,0,1,out->len+n);
    memmove(out->data+out->len,p,(size_t)n); out->len+=n;
}
static GClosure *g_closure(void *function,int64_t n) { GClosure *c=g_alloc(sizeof *c+(size_t)n*sizeof(GRef)); c->function=function; c->count=n; return c; }
typedef struct GActivation {
    struct GActivation *parent; int64_t base,count; GWatermark *marks;GPublication *publications;unsigned char *fixed;
} GActivation;
static _Thread_local GActivation *g_activation_top;
static void g_activation_enter(GActivation *frame,int64_t base,int64_t count,GWatermark *marks) {
    *frame=(GActivation){g_activation_top,base,count,marks,g_publication_top,g_fixed_region.stack.top};
    g_mark_regions(base,count,marks);g_activation_top=frame;
}
static void g_activation_leave(GActivation *frame) {
    g_fixed_region.stack.top=frame->fixed;if(!g_fixed_region.stack.top)g_fixed_region.stack.top=g_fixed_region.base;
    g_restore_regions(frame->base,frame->count,frame->marks);g_activation_top=frame->parent;g_publication_top=frame->publications;
}
typedef struct GReturnFrame {
    struct GReturnFrame *parent;int64_t function;jmp_buf jump;void *result;size_t size;
    void (*publish)(void *,const void *);GActivation *activation;
} GReturnFrame;
static _Thread_local GReturnFrame *g_return_top;
static void *g_return_destination(int64_t function) {
    GReturnFrame *frame=g_return_top;while(frame && frame->function!=function)frame=frame->parent;
    if(!frame)g_panic("nonlocal return target is not active");return frame->result;
}
static void g_throw(int64_t function,const void *value,size_t size) {
    GReturnFrame *f=g_return_top;
    while(f && f->function!=function)f=f->parent;
    if(!f || f->size!=size)g_panic("nonlocal return target is not active");
    if(size)f->publish(f->result,value);
    while(g_activation_top && g_activation_top!=f->activation)g_activation_leave(g_activation_top);
    g_return_top=f;longjmp(f->jump,1);
}
static int64_t g_div(int64_t a,int64_t b,const char *file,int line) { if(!b) g_panic_at("division by zero",file,line); if(a==INT64_MIN && b==-1) g_panic_at("integer overflow in division",file,line); return a/b; }
static int64_t g_mod(int64_t a,int64_t b,const char *file,int line) { if(!b) g_panic_at("division by zero",file,line); if(a==INT64_MIN && b==-1) return 0; int64_t r=a%b; if(r<0) { uint64_t magnitude=(uint64_t)b; if(b<0) magnitude=0-magnitude; return (int64_t)((uint64_t)r+magnitude); } return r; }
static uint64_t g_udiv(uint64_t a,uint64_t b,const char *file,int line) { if(!b) g_panic_at("division by zero",file,line); return a/b; }
static uint64_t g_umod(uint64_t a,uint64_t b,const char *file,int line) { if(!b) g_panic_at("division by zero",file,line); return a%b; }
static double g_mul_add(double x,double y,double z) { volatile double product=x*y;return product+z; }
static float g_mul_addf(float x,float y,float z) { volatile float product=x*y;return product+z; }
static int64_t g_find_any(GSlice s,GRef set) { const unsigned char *p=g_address(s.base),*members=g_address(set);for(int64_t i=0;i<s.len;i++) if(members[p[i]]) return i;return -1; }
static int64_t g_find_pair(GSlice s,GRef a,int64_t d,GRef b) { if(d<0 || d>=s.len) return -1;const unsigned char *p=g_address(s.base),*first=g_address(a),*second=g_address(b);for(int64_t i=0;i<s.len-d;i++) if(first[p[i]] && second[p[i+d]]) return i;return -1; }
static uint64_t g_float_wrap(double a) { if(a!=a)return 0;if(!isfinite(a)) g_panic("float conversion is not finite");int negative=a<0;double magnitude=fmod(trunc(fabs(a)),18446744073709551616.0);uint64_t bits;if(magnitude>=9223372036854775808.0) bits=((uint64_t)(magnitude-9223372036854775808.0))+(UINT64_C(1)<<63);else bits=(uint64_t)magnitude;if(negative) bits=0-bits;return bits; }
static void g_print_bytes(GArray *out,const void *p,int64_t n) { if(out) g_bytes(out,p,n); else if(n) fwrite(p,1,(size_t)n,stdout); }
static void g_print_text(GArray *out,const char *s) { g_print_bytes(out,s,(int64_t)strlen(s)); }
static char *g_path(GSlice p) { if(p.len<0 || p.len>=4096) return NULL; char *s=g_alloc((size_t)p.len+1); if(p.len) memcpy(s,g_address(p.base),(size_t)p.len); if(memchr(s,0,(size_t)p.len)) return NULL; return s; }
static int g_os_read_file(GSlice path,GRef out) { char *s=g_path(path); if(!s) return 0; FILE *f=fopen(s,"rb"); if(!f) return 0; GArray a; memcpy(&a,g_address(out),sizeof a); unsigned char b[16384]; size_t n; while((n=fread(b,1,sizeof b,f))) g_bytes(&a,b,(int64_t)n); int ok=!ferror(f); fclose(f); memcpy(g_address(out),&a,sizeof a); return ok; }
static int g_os_write_file(GSlice path,GSlice data,const char *mode) { char *s=g_path(path); if(!s) return 0; FILE *f=fopen(s,mode); if(!f) return 0; int ok=fwrite(g_address(data.base),1,(size_t)data.len,f)==(size_t)data.len; return fclose(f)==0 && ok; }
static int g_os_write_atomic(GSlice path,GSlice data) { char *s=g_path(path); if(!s) return 0; size_t n=strlen(s); char *tmp=g_alloc(n+16); memcpy(tmp,s,n); memcpy(tmp+n,".tmp-XXXXXX",12); int fd=mkstemp(tmp); if(fd<0) return 0; FILE *f=fdopen(fd,"wb"); if(!f) { close(fd); unlink(tmp); return 0; } int ok=fwrite(g_address(data.base),1,(size_t)data.len,f)==(size_t)data.len; if(fflush(f)||fsync(fd)) ok=0; if(fclose(f)) ok=0; if(ok && rename(tmp,s)) ok=0; if(!ok) unlink(tmp); return ok; }
static int g_os_kind(GSlice path) { char *s=g_path(path); struct stat st; if(!s || stat(s,&st)) return 0; if(S_ISDIR(st.st_mode)) return 2; return 1; }
static int g_os_line(GRef out) { GArray a; memcpy(&a,g_address(out),sizeof a); int c; int any=0; while((c=fgetc(stdin))!=EOF) { any=1; if(c==10) break; unsigned char b=(unsigned char)c; g_bytes(&a,&b,1); } if(a.len && a.data[a.len-1]==13) a.len--; memcpy(g_address(out),&a,sizeof a); return any; }
static void g_os_stdin(GRef out) { GArray a; memcpy(&a,g_address(out),sizeof a); unsigned char b[16384]; size_t n; while((n=fread(b,1,sizeof b,stdin))) g_bytes(&a,b,(int64_t)n); memcpy(g_address(out),&a,sizeof a); }
static void g_os_arg(int64_t i,GRef out) { if(i<0 || i>=g_argc) return; GArray a; memcpy(&a,g_address(out),sizeof a); g_bytes(&a,g_argv[i],(int64_t)strlen(g_argv[i])); memcpy(g_address(out),&a,sizeof a); }
static int g_os_env(GSlice name,GRef out) { char *n=g_path(name); const char *v=NULL; if(n) v=getenv(n); if(!v) return 0; GArray a; memcpy(&a,g_address(out),sizeof a); g_bytes(&a,v,(int64_t)strlen(v)); memcpy(g_address(out),&a,sizeof a); return 1; }
static int64_t g_os_time(int monotonic) { struct timespec t; clockid_t c=CLOCK_REALTIME; if(monotonic) c=CLOCK_MONOTONIC; if(clock_gettime(c,&t)) return 0; return (int64_t)t.tv_sec*1000000000+t.tv_nsec; }
static void g_os_sleep(int64_t ms) { if(ms<0) return; struct timespec t={ms/1000,(ms%1000)*1000000}; while(nanosleep(&t,&t) && errno==EINTR) {} }
static uint64_t g_os_random(void) { uint64_t n=0; FILE *f=fopen("/dev/urandom","rb"); if(f) { if(fread(&n,1,sizeof n,f)!=sizeof n) n=0; fclose(f); } if(!n) n=(uint64_t)g_os_time(0)^(uint64_t)(uintptr_t)&n; n^=n>>30; n*=UINT64_C(0xbf58476d1ce4e5b9); n^=n>>27; n*=UINT64_C(0x94d049bb133111eb); return n^(n>>31); }
static int g_sort_names(const void *a,const void *b) { return strcmp(*(const char *const *)a,*(const char *const *)b); }
static int g_os_list(GSlice path,GRef out) { char *s=g_path(path); if(!s) return 0; DIR *d=opendir(s); if(!d) return 0; char **names=NULL; size_t n=0,cap=0; struct dirent *e; while((e=readdir(d))) { if(!strcmp(e->d_name,".") || !strcmp(e->d_name,"..") || strchr(e->d_name,10)) continue; if(n==cap) { cap=cap*2+16; names=realloc(names,cap*sizeof *names); if(!names) gs_panic("out of memory"); } names[n]=strdup(e->d_name); n++; } closedir(d); qsort(names,n,sizeof *names,g_sort_names); GArray a; memcpy(&a,g_address(out),sizeof a); for(size_t i=0;i<n;i++) { g_bytes(&a,names[i],(int64_t)strlen(names[i])); g_bytes(&a,"\n",1); free(names[i]); } free(names); memcpy(g_address(out),&a,sizeof a); return 1; }

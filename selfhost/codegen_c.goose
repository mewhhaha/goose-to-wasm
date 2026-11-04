import model;
import std;
import checker_rendering;

// Native C lowering shares the checked ID-based IR with the direct Wasm path.
// Runtime text contains storage/OS/formatting only; it never invokes a compiler.
let cc_runtime = """
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
typedef uint64_t GRef;
#define G_MOVING_REF UINT64_C(0x8000000000000000)
#define G_OWNER_REF UINT64_C(0x4000000000000000)
#define G_REF_TAGS (G_MOVING_REF|G_OWNER_REF)
#define G_REF_OFFSET UINT64_C(0xffffffff)
typedef struct { GRef slot; uint32_t id; } GRootSlot;
static GRootSlot *g_root_slots;
static GRef *g_roots;
static uint32_t g_root_count, g_root_capacity;
typedef struct { GRef base; int64_t len; } GSlice;
typedef struct { unsigned char *data; int64_t len, cap; } GArray;
typedef struct GClosure { void *function; int64_t count; GRef captures[]; } GClosure;
typedef struct GAllocation { struct GAllocation *next; void *data; } GAllocation;
static GAllocation *g_allocations;
static int g_argc; static char **g_argv;
static void g_panic(const char *s) { fprintf(stderr,"goose runtime error: %s\n",s); exit(1); }
static void g_panic_at(const char *s,const char *file,int line) { fprintf(stderr,"goose runtime error: %s (%s:%d)\n",s,file,line);exit(1); }
static void g_index_fail(int64_t index,int64_t len,const char *file,int line) {
    fprintf(stderr,"goose runtime error: index %" PRId64 " out of bounds (length %" PRId64 ")",index,len);
    if(file)fprintf(stderr," (%s:%d)",file,line);fputc('\n',stderr);exit(1);
}
static void *g_alloc(size_t n) {
    void *p=calloc(1,n+!n); if(!p) g_panic("out of memory");
    GAllocation *a=malloc(sizeof *a); if(!a) g_panic("out of memory");
    a->data=p; a->next=g_allocations; g_allocations=a; return p;
}
static void g_cleanup(void) { while(g_allocations) { GAllocation *a=g_allocations; g_allocations=a->next; free(a->data); free(a); } }
/* Direct locations are ordinary addresses. A location in a growable owner
   encodes the owner-header ID plus its byte offset, so table growth does not
   allocate a reference object for each read and retained views follow growth. */
static uint64_t g_root_hash(GRef value) {
    value^=value>>33; value*=UINT64_C(0xff51afd7ed558ccd);
    value^=value>>33; value*=UINT64_C(0xc4ceb9fe1a85ec53); return value^(value>>33);
}
static void g_root_grow(void) {
    uint32_t capacity=g_root_capacity*2;
    if(!capacity) capacity=1024;
    if(capacity<g_root_capacity) g_panic("too many array owners");
    GRootSlot *slots=g_alloc((size_t)capacity*sizeof *slots);
    GRef *roots=g_alloc((size_t)capacity*sizeof *roots);
    if(g_root_count) memcpy(roots,g_roots,(size_t)(g_root_count+1)*sizeof *roots);
    for(uint32_t i=0;i<g_root_capacity;i++) {
        GRootSlot item=g_root_slots[i]; if(!item.slot)continue;
        uint32_t at=(uint32_t)g_root_hash(item.slot)&(capacity-1);
        while(slots[at].slot) at=(at+1)&(capacity-1);
        slots[at]=item;
    }
    g_root_slots=slots;g_roots=roots;g_root_capacity=capacity;
}
static uint32_t g_root_id(GRef slot) {
    if(!slot)g_panic("null array owner");
    if(!g_root_capacity)g_root_grow();
    uint32_t at=(uint32_t)g_root_hash(slot)&(g_root_capacity-1);
    while(g_root_slots[at].slot) {
        if(g_root_slots[at].slot==slot)return g_root_slots[at].id;
        at=(at+1)&(g_root_capacity-1);
    }
    if((uint64_t)(g_root_count+1)*2>=g_root_capacity) {
        g_root_grow();at=(uint32_t)g_root_hash(slot)&(g_root_capacity-1);
        while(g_root_slots[at].slot)at=(at+1)&(g_root_capacity-1);
    }
    if(g_root_count>=UINT32_C(0x3ffffffe))g_panic("too many array owners");
    uint32_t id=++g_root_count;g_roots[id]=slot;
    g_root_slots[at].slot=slot;g_root_slots[at].id=id;return id;
}
static GRef g_ref(void *p) {
    GRef value=(GRef)(uintptr_t)p;
    if(value&G_REF_TAGS)g_panic("native address exceeds reference representation");return value;
}
static unsigned char *g_address(GRef ref) {
    if(!ref)g_panic("null reference");
    if(!(ref&G_REF_TAGS))return (unsigned char *)(uintptr_t)ref;
    uint32_t id=(uint32_t)((ref&~G_REF_TAGS)>>32);
    if(!id || id>g_root_count)g_panic("invalid array owner reference");
    unsigned char *base=g_address(g_roots[id]);
    if(ref&G_MOVING_REF)memcpy(&base,base,sizeof base);
    uint64_t offset=ref&G_REF_OFFSET;
    if(!offset)return base;
    if(!base)g_panic("null reference");return base+offset;
}
static GRef g_offset(GRef ref,int64_t offset) {
    if(offset<0)g_panic("negative reference offset");
    if(ref&G_REF_TAGS) {
        uint64_t sum=(ref&G_REF_OFFSET)+(uint64_t)offset;
        if(sum>G_REF_OFFSET)g_panic("array reference offset exceeds addressable memory");
        return (ref&~G_REF_OFFSET)|sum;
    }
    if(!ref && offset)g_panic("null reference");return ref+(uint64_t)offset;
}
static GRef g_owner(GRef root) {
    if(!root)return 0;
    if((root&G_REF_TAGS)==G_OWNER_REF && !(root&G_REF_OFFSET))return root;
    return G_OWNER_REF|((uint64_t)g_root_id(root)<<32);
}
static GRef g_moving(GRef root,int64_t offset) {
    if(offset<0 || (uint64_t)offset>G_REF_OFFSET)g_panic("array reference offset exceeds addressable memory");
    uint64_t owner;
    if((root&G_REF_TAGS)==G_OWNER_REF && !(root&G_REF_OFFSET)) owner=root&~G_REF_TAGS;
    else owner=(uint64_t)g_root_id(root)<<32;
    return G_MOVING_REF|owner|(uint64_t)offset;
}
static uint64_t g_read_length(const void *p,int n) { uint64_t v=0; memcpy(&v,p,n); return v; }
static void g_write_length(void *p,int n,uint64_t v) { memcpy(p,&v,n); }
static int64_t g_len(GRef r,int kind,int64_t fixed,int prefix) {
    if(kind==5) { GSlice s; memcpy(&s,g_address(r),sizeof s); return s.len; }
    if(kind==0) return fixed;
    if(kind==2 && fixed>=0) return (int64_t)g_read_length(g_address(r),prefix);
    GArray a; memcpy(&a,g_address(r),sizeof a); return a.len;
}
static int64_t g_cap(GRef r,int kind,int64_t fixed) {
    if(kind==0) return fixed;
    if(kind==2 && fixed>=0) return fixed;
    GArray a; memcpy(&a,g_address(r),sizeof a); return a.cap;
}
static GRef g_element_at(GRef r,int kind,int64_t fixed,int prefix,int64_t width,int64_t index,int allow_end,const char *file,int line) {
    int64_t len=g_len(r,kind,fixed,prefix);
    if(index<0 || index>len || (!allow_end && index==len))g_index_fail(index,len,file,line);
    if(width && index>INT64_MAX/width) g_panic("array offset overflow");
    if(kind==5) { GSlice s; memcpy(&s,g_address(r),sizeof s); return g_offset(s.base,index*width); }
    if(kind==0) return g_offset(r,index*width);
    if(kind==2 && fixed>=0) return g_offset(r,prefix+index*width);
    return g_moving(r,index*width);
}
static GRef g_element(GRef r,int kind,int64_t fixed,int prefix,int64_t width,int64_t index,int allow_end) {
    return g_element_at(r,kind,fixed,prefix,width,index,allow_end,NULL,0);
}
static GSlice g_view(GRef r,int kind,int64_t fixed,int prefix,int64_t width) {
    GSlice s={g_element(r,kind,fixed,prefix,width,0,1),g_len(r,kind,fixed,prefix)}; return s;
}
static void g_reserve(GRef r,int kind,int64_t fixed,int prefix,int64_t width,int64_t count) {
    if(count<0 || (width && count>INT64_MAX/width)) g_panic("invalid capacity");
    if(kind==2 && fixed>=0) { if(count>fixed) g_panic("limited array capacity exceeded"); return; }
    if(kind!=1 && kind!=3 && kind!=4 && kind!=2) g_panic("array cannot grow");
    GArray a; memcpy(&a,g_address(r),sizeof a);
    if(kind==2) {
        if(!a.data) { a.data=g_alloc((size_t)(count*width));a.cap=count;memcpy(g_address(r),&a,sizeof a);return; }
        if(count>a.cap) g_panic("limited array capacity exceeded");return;
    }
    if(count>a.cap) {
        int64_t cap=a.cap*2+8; if(cap<count) cap=count;
        if(width && cap>INT64_MAX/width) g_panic("array capacity overflow");
        unsigned char *data=g_alloc((size_t)(cap*width));
        if(a.len) memcpy(data,a.data,(size_t)(a.len*width)); a.data=data; a.cap=cap;
        memcpy(g_address(r),&a,sizeof a);
    }
}
static void g_set_len(GRef r,int kind,int64_t fixed,int prefix,int64_t count) {
    if(kind==2 && fixed>=0) g_write_length(g_address(r),prefix,(uint64_t)count);
    else { GArray a; memcpy(&a,g_address(r),sizeof a); a.len=count; memcpy(g_address(r),&a,sizeof a); }
}
static GRef g_push(GRef r,int kind,int64_t fixed,int prefix,int64_t width,const void *v) {
    int64_t n=g_len(r,kind,fixed,prefix); g_reserve(r,kind,fixed,prefix,width,n+1);
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
typedef struct GReturnFrame { struct GReturnFrame *parent; int64_t function; jmp_buf jump; void *result; size_t size; } GReturnFrame;
static _Thread_local GReturnFrame *g_return_top;
static void g_throw(int64_t function,const void *value,size_t size) {
    GReturnFrame *f=g_return_top;
    while(f && f->function!=function) f=f->parent;
    if(!f || f->size!=size) g_panic("nonlocal return target is not active");
    if(size) memcpy(f->result,value,size); g_return_top=f; longjmp(f->jump,1);
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
static int g_os_list(GSlice path,GRef out) { char *s=g_path(path); if(!s) return 0; DIR *d=opendir(s); if(!d) return 0; char **names=NULL; size_t n=0,cap=0; struct dirent *e; while((e=readdir(d))) { if(!strcmp(e->d_name,".") || !strcmp(e->d_name,"..") || strchr(e->d_name,10)) continue; if(n==cap) { cap=cap*2+16; names=realloc(names,cap*sizeof *names); if(!names) g_panic("out of memory"); } names[n]=strdup(e->d_name); n++; } closedir(d); qsort(names,n,sizeof *names,g_sort_names); GArray a; memcpy(&a,g_address(out),sizeof a); for(size_t i=0;i<n;i++) { g_bytes(&a,names[i],(int64_t)strlen(names[i])); g_bytes(&a,"\n",1); free(names[i]); } free(names); memcpy(g_address(out),&a,sizeof a); return 1; }

#define GS_CHECKED_STACKS 0
static void g_format_bounds(void *p,uint64_t n) { (void)p; (void)n; }
static const char gs_digit_pairs[201] =
    "00010203040506070809101112131415161718192021222324252627282930313233343536373839"
    "40414243444546474849505152535455565758596061626364656667686970717273747576777879"
    "8081828384858687888990919293949596979899";

static int gs_fmt_digits(uint64_t v) {
    int n = 1;
    for (;;) {
        if (v < 10) return n;
        if (v < 100) return n + 1;
        if (v < 1000) return n + 2;
        if (v < 10000) return n + 3;
        v /= 10000;
        n += 4;
    }
}

static int64_t gs_fmt_u64(uint8_t *dst, uint64_t v) {
    int n = gs_fmt_digits(v);

    uint8_t *p = dst + n;
    while (v >= 100) {
        unsigned r = (unsigned)(v % 100);
        v /= 100;
        p -= 2;
        p[0] = (uint8_t)gs_digit_pairs[2 * r];
        p[1] = (uint8_t)gs_digit_pairs[2 * r + 1];
    }
    if (v >= 10) {
        p[-2] = (uint8_t)gs_digit_pairs[2 * v];
        p[-1] = (uint8_t)gs_digit_pairs[2 * v + 1];
    } else {
        p[-1] = (uint8_t)('0' + v);
    }
    return n;
}

static int64_t gs_fmt_i64(uint8_t *dst, int64_t v) {
    if (v >= 0) return gs_fmt_u64(dst, (uint64_t)v);
    /* The magnitude in unsigned arithmetic, so i64.min needs no case. */

    dst[0] = '-';
    return 1 + gs_fmt_u64(dst + 1, 0 - (uint64_t)v);
}

/* A float's text is the fewest significant digits that read back as the
   same value of its own type and, of those, the ones nearest it, a tie going
   to the even digit (as Python's repr and Ryu choose). They are found in
   integers, by Burger and Dybvig's free-format algorithm, not through the C
   library: msvcrt, which tcc uses on Windows, rounds a printf tie away from
   zero, and below a power of two the gap to the next float is half the gap
   above, so the shortest text can lie above the value while the correctly
   rounded spelling of that length, below it, does not read back.

   The numbers are naturals in 32-bit limbs, least significant first. The
   denominator s stays below 2^1079 (ten times 2^1075, for the smallest
   doubles), and the others below eleven times s. */
typedef struct { int n; uint32_t d[36]; } gs_big;

/* a = v << sh, for v > 0. */
static void gs_big_set(gs_big *a, uint64_t v, int sh) {
    int w = sh >> 5, b = sh & 31, i;
    uint64_t lo = v << b, hi = b ? v >> (64 - b) : 0;
    for (i = 0; i < w; i++) a->d[i] = 0;
    a->d[w] = (uint32_t)lo;
    a->d[w + 1] = (uint32_t)(lo >> 32);
    a->d[w + 2] = (uint32_t)hi;
    a->n = w + 3;
    while (!a->d[a->n - 1]) a->n--;
}

static void gs_big_mul(gs_big *a, uint32_t m) {
    uint64_t c = 0;
    for (int i = 0; i < a->n; i++) {
        c += (uint64_t)a->d[i] * m;
        a->d[i] = (uint32_t)c;
        c >>= 32;
    }
    if (c) a->d[a->n++] = (uint32_t)c;
}

static void gs_big_mul_pow10(gs_big *a, int k) {
    for (; k >= 9; k -= 9) gs_big_mul(a, 1000000000u);
    for (; k > 0; k--) gs_big_mul(a, 10);
}

static int gs_big_cmp(const gs_big *a, const gs_big *b) {
    if (a->n != b->n) return a->n < b->n ? -1 : 1;
    for (int i = a->n - 1; i >= 0; i--)
        if (a->d[i] != b->d[i]) return a->d[i] < b->d[i] ? -1 : 1;
    return 0;
}

/* t = a + b */
static void gs_big_add(gs_big *t, const gs_big *a, const gs_big *b) {
    int n = a->n > b->n ? a->n : b->n;
    uint64_t c = 0;
    for (int i = 0; i < n; i++) {
        c += (uint64_t)(i < a->n ? a->d[i] : 0) + (i < b->n ? b->d[i] : 0);
        t->d[i] = (uint32_t)c;
        c >>= 32;
    }
    t->n = n;
    if (c) t->d[t->n++] = (uint32_t)c;
}

/* a -= b, for a >= b. */
static void gs_big_sub(gs_big *a, const gs_big *b) {
    uint64_t borrow = 0;
    for (int i = 0; i < a->n; i++) {
        uint64_t x = (uint64_t)a->d[i] - (i < b->n ? b->d[i] : 0) - borrow;
        a->d[i] = (uint32_t)x;
        borrow = x >> 63;
    }
    while (a->n && !a->d[a->n - 1]) a->n--;
}

/* The shortest digits of f * 2^e (f > 0) as a float of `bits` significant
   bits and least exponent emin, into dig; returns their count and sets *k
   so that the value they spell is 0.d1d2... * 10^*k. */
static int gs_float_digits(uint64_t f, int e, int bits, int emin, char *dig, int *k) {
    gs_big r, s, mp, mlo, t;
    /* Reading rounds a tie to the even significand, so the interval that
       reads back as f * 2^e includes its ends when f is even. */
    int even = !(f & 1);
    /* Below a power of two, the gap to the next float down is half the gap up. */
    int asym = f == (uint64_t)1 << (bits - 1) && e > emin;
    int up = e > 0 ? e : 0, lg = e - 1, n = 0, c;
    /* The value is r / s, and what reads back as it reaches from (r - *mm) / s
       to (r + mp) / s: half the gap to each neighbour. */
    gs_big *mm = asym ? &mlo : &mp;
    gs_big_set(&r, f, up + 1 + asym);
    gs_big_set(&s, 1, up - e + 1 + asym);
    gs_big_set(&mp, 1, up + asym);
    gs_big_set(&mlo, 1, up);
    /* Scale to 10^*k, the least power of ten above the interval: with
       lg = floor(log2 value), ceil(lg log10 2) is it or one short, and
       78913 / 2^18 is log10 2 closely enough to compute that for |lg| < 1650. */
    for (uint64_t g = f; g; g >>= 1) lg++;
    *k = lg > 0 ? ((lg * 78913) >> 18) + 1 : -((-lg * 78913) >> 18);
    if (*k >= 0) gs_big_mul_pow10(&s, *k);
    else {
        gs_big_mul_pow10(&r, -*k);
        gs_big_mul_pow10(&mp, -*k);
        if (asym) gs_big_mul_pow10(&mlo, -*k);
    }
    gs_big_add(&t, &r, &mp);
    c = gs_big_cmp(&t, &s);
    if (even ? c >= 0 : c > 0) {
        gs_big_mul(&s, 10);
        ++*k;
    }
    /* Each digit d leaves the remainder r: stop where the digits so far
       followed by d (r within *mm) or by d + 1 (r + mp past s) read back. */
    for (;;) {
        int d = 0, low, high;
        gs_big_mul(&r, 10);
        gs_big_mul(&mp, 10);
        if (asym) gs_big_mul(&mlo, 10);
        while (gs_big_cmp(&r, &s) >= 0) {
            gs_big_sub(&r, &s);
            d++;
        }
        c = gs_big_cmp(&r, mm);
        low = even ? c <= 0 : c < 0;
        gs_big_add(&t, &r, &mp);
        c = gs_big_cmp(&t, &s);
        high = even ? c >= 0 : c > 0;
        if (!low && !high) {
            dig[n++] = (char)('0' + d);
            continue;
        }
        if (low && high) {
            /* Both read back: the nearer, d + 1 when r is past half of s,
               and of two as near, the even one. */
            gs_big_add(&t, &r, &r);
            c = gs_big_cmp(&t, &s);
            high = c > 0 || (c == 0 && (d & 1));
        }
        dig[n++] = (char)('0' + d + high);
        return n;
    }
}

/* The text of a finite float from its fields: the sign, the significand
   without its implicit bit and the biased exponent, for a type of `bits`
   significant bits and least exponent emin. The digits are laid out as C's
   %g lays them out at a precision of max(15, digits): in exponent form, with
   at least two exponent digits, below 1e-4 or from that power of ten up. */
static int64_t gs_fmt_float_unchecked(uint8_t *dst, int neg, uint64_t frac, int bexp, int bits,
                            int emin) {
    char dig[20], *p = (char *)dst;
    int k, n, x, i;
    if (neg) *p++ = '-';
    if (!frac && !bexp) {
        memcpy(p, "0.0", 3);
        return p + 3 - (char *)dst;
    }
    n = gs_float_digits(bexp ? frac | (uint64_t)1 << (bits - 1) : frac,
                        (bexp ? bexp - 1 : 0) + emin, bits, emin, dig, &k);
    x = k - 1;
    if (x < -4 || x >= (n > 15 ? n : 15)) {
        *p++ = dig[0];
        if (n > 1) *p++ = '.';
        for (i = 1; i < n; i++) *p++ = dig[i];
        *p++ = 'e';
        *p++ = x < 0 ? '-' : '+';
        if (x < 0) x = -x;
        if (x >= 100) *p++ = (char)('0' + x / 100);
        *p++ = (char)('0' + x / 10 % 10);
        *p++ = (char)('0' + x % 10);
    } else if (x < 0) {
        *p++ = '0';
        *p++ = '.';
        for (i = -1; i > x; i--) *p++ = '0';
        for (i = 0; i < n; i++) *p++ = dig[i];
    } else {
        for (i = 0; i < n || i <= x; i++) {
            if (i == x + 1) *p++ = '.';
            *p++ = i < n ? dig[i] : '0';
        }
        /* A whole number still reads as a float: 1.0, not 1. */
        if (n <= x + 1) {
            *p++ = '.';
            *p++ = '0';
        }
    }
    return p - (char *)dst;
}

static int64_t gs_fmt_float(uint8_t *dst, int neg, uint64_t frac, int bexp, int bits,
                            int emin) {
#if GS_CHECKED_STACKS
    /* Determine the exact length before touching a data stack. The longest
       f64 spelling fits in 32 bytes, including sign and three exponent digits. */
    uint8_t text[32];
    int64_t n = gs_fmt_float_unchecked(text, neg, frac, bexp, bits, emin);

    memcpy(dst, text, (size_t)n);
    return n;
#else
    return gs_fmt_float_unchecked(dst, neg, frac, bexp, bits, emin);
#endif
}

static int64_t gs_fmt_f64(uint8_t *dst, double v) {
    uint64_t b;
    /* C libraries disagree here (msvcrt, which tcc uses on Windows, writes
       1.#INF and -1.#IND; others give a NaN's sign bit, which depends on
       the CPU that made it), so these are spelled by the runtime. */
    if (v != v) { g_format_bounds(dst, 3); memcpy(dst, "nan", 3); return 3; }
    if (isinf(v)) {
        if (v > 0) { g_format_bounds(dst, 3); memcpy(dst, "inf", 3); return 3; }
        g_format_bounds(dst, 4);
        memcpy(dst, "-inf", 4);
        return 4;
    }
    memcpy(&b, &v, sizeof b);
    return gs_fmt_float(dst, (int)(b >> 63), b & (((uint64_t)1 << 52) - 1),
                        (int)(b >> 52) & 0x7FF, 53, -1074);
}

/* The digits are the f32's own, laid out as an f64's are, so 0.1 as an f32
   prints as 0.1, not as the digits of the f64 it widens to. */
static int64_t gs_fmt_f32(uint8_t *dst, float v) {
    double d = v;
    uint32_t b;
    if (d != d || isinf(d)) return gs_fmt_f64(dst, d);
    memcpy(&b, &v, sizeof b);
    return gs_fmt_float(dst, (int)(b >> 31), b & 0x7FFFFF, (int)(b >> 23) & 0xFF, 24, -149);
}

static int64_t gs_fmt_bool(uint8_t *dst, int64_t v) {

    memcpy(dst, v ? "true" : "false", v ? 4 : 5);
    return v ? 4 : 5;
}

static int64_t gs_fmt_quoted(uint8_t *dst, const uint8_t *s, int64_t n) {
#if GS_CHECKED_STACKS
    uint64_t size = 2;
    for (int64_t i = 0; i < n; i++) {
        uint8_t c = s[i];
        uint64_t part = 1;
        if (c == '"' || c == '\\' || c == '\n' || c == '\r' || c == '\t') part++;
        if (size > UINT64_MAX - part) gs_panic("data stack overflow: quoted text size");
        size += part;
    }
    g_format_bounds(dst, size);
#endif
    uint8_t *d = dst;
    *d++ = '"';
    for (int64_t i = 0; i < n; i++) {
        uint8_t c = s[i];
        switch (c) {
            case '"': *d++ = '\\'; *d++ = '"'; break;
            case '\\': *d++ = '\\'; *d++ = '\\'; break;
            case '\n': *d++ = '\\'; *d++ = 'n'; break;
            case '\r': *d++ = '\\'; *d++ = 'r'; break;
            case '\t': *d++ = '\\'; *d++ = 't'; break;
            default: *d++ = c; break;
        }
    }
    *d++ = '"';
    return (int64_t)(d - dst);
}

""";

struct CcExit { node: i64, done: i64, again: i64 = -1, result: i64 = -1, type_id: i64 = TYPE_VOID }
struct CcBody {
    out: u8[>..]&, exits: CcExit[>..]&, work: i64[>..]&, function: i64 = -1,
    serial: i64 = 0, result_type: i64 = TYPE_VOID,
}
fn cc_text(out: u8[>..]&, text: const u8[:]) { out.append(text); }
fn cc_number(out: u8[>..]&, value: i64) { out.format(value); }
fn cc_id(out: u8[>..]&, prefix: const u8[:], id: i64) { cc_text(out, prefix); cc_number(out, id); }
fn cc_type(out: u8[>..]&, type_id: i64) { cc_id(out, "g_t", type_id); }
fn cc_fail(p: Program&, node: i64, message: const u8[:]) {
    var token: i64 = -1; if node >= 0 && node < p.nodes.len { token = p.nodes[node].token; }
    diagnose(p, token, message);
}
fn cc_kind(p: Program&, type_id: i64) -> i64 {
    if type_id < 0 || type_id >= p.types.len { return TY_UNKNOWN; } return p.types[type_id].kind;
}
fn cc_aggregate(p: Program&, type_id: i64) -> bool {
    let kind = cc_kind(p, type_id); return kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM || kind == TY_TUPLE;
}
fn cc_owner(p: Program&, type_id: i64) -> bool {
    if cc_kind(p, type_id) != TY_ARRAY { return false; }
    let t = p.types[type_id]; return t.array_kind != A_FIXED && !(t.array_kind == A_LIMITED && t.count >= 0);
}
fn cc_array_kind(p: Program&, type_id: i64) -> i64 {
    if cc_kind(p, type_id) == TY_SLICE { return A_SLICE; } return p.types[type_id].array_kind;
}
fn cc_prefix(p: Program&, type_id: i64) -> i64 {
    let t = p.types[type_id]; if t.array_kind != A_LIMITED || t.count < 0 { return 0; }
    if t.length_storage > 0 { return t.length_storage; } return 1;
}
fn cc_array_args(p: Program&, out: u8[>..]&, type_id: i64, width: bool = true) {
    let t = p.types[type_id]; cc_number(out, cc_array_kind(p, type_id)); cc_text(out, ",");
    cc_number(out, t.count); cc_text(out, ","); cc_number(out, cc_prefix(p, type_id));
    if width { cc_text(out, ","); cc_number(out, p.types[t.element].size); }
}
fn cc_temp(p: Program&, f: CcBody&, type_id: i64, zero: bool = true) -> i64 {
    if cc_kind(p, type_id) == TY_VOID { return -1; }
    if type_id < 0 { cc_fail(p, f.function, "c: expression lacks a checked type"); return -1; }
    if p.types[type_id].storage != 0 ||
       p.types[type_id].kind == TY_REF && p.types[type_id].length_storage >= 0 {
        cc_fail(p, f.function, "c: encoded integer/reference image layout requires packed-image lowering");
    }
    let id = f.serial; f.serial++;
    cc_type(f.out, type_id); cc_text(f.out, " "); cc_id(f.out, "g_v", id);
    if zero { cc_text(f.out, "="); cc_zero_initializer(p, f.out, type_id); }
    cc_text(f.out, ";\n"); return id;
}
fn cc_ref_temp(f: CcBody&) -> i64 {
    let id = f.serial; f.serial++; cc_id(f.out, "GRef g_v", id); cc_text(f.out, "=0;\n"); return id;
}
fn cc_set(f: CcBody&, id: i64) { cc_id(f.out, "g_v", id); cc_text(f.out, "="); }
fn cc_load(p: Program&, f: CcBody&, ref: i64, type_id: i64) -> i64 {
    let value = cc_temp(p, f, type_id); if value < 0 { return value; }
    cc_set(f, value); cc_id(f.out, "g_load_", type_id); cc_text(f.out, "("); cc_id(f.out, "g_v", ref); cc_text(f.out, ");\n"); return value;
}
fn cc_store(f: CcBody&, ref: i64, value: i64, type_id: i64) {
    if ref < 0 || value < 0 { return; }
    cc_id(f.out, "g_store_", type_id); cc_text(f.out, "("); cc_id(f.out, "g_v", ref); cc_text(f.out, ","); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n");
}
fn cc_temporary_ref(f: CcBody&, value: i64) -> i64 {
    let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); return ref;
}
fn cc_symbol_ref(p: Program&, f: CcBody&, symbol: i64, node: i64) -> i64 {
    if symbol < 0 || symbol >= p.symbols.len { cc_fail(p, node, "c: unresolved place"); return -1; }
    let s = p.symbols[symbol]; let ref = cc_ref_temp(f); cc_set(f, ref);
    if s.owner < 0 || s.owner == f.function || (s.flags & S_GLOBAL) != 0 {
        cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_s", symbol); cc_text(f.out, ");\n"); return ref;
    }
    var capture = p.nodes[f.function].captures; var index = 0;
    while capture >= 0 {
        if p.nodes[capture].symbol == symbol {
            cc_text(f.out, "g_env->captures["); cc_number(f.out, index); cc_text(f.out, "];\n"); return ref;
        }
        index++; capture = p.nodes[capture].next;
    }
    cc_text(f.out, "0;\n"); cc_fail(p, node, "c: captured variable missing from closure environment"); return -1;
}
recursive fn cc_base(p: Program&, f: CcBody&, node: i64) -> i64 {
    if cc_kind(p, p.nodes[node].type_id) == TY_REF { return cc_expr(p, f, node); }
    return cc_place(p, f, node);
}
recursive fn cc_place(p: Program&, f: CcBody&, node: i64) -> i64 {
    if node < 0 { cc_fail(p, node, "c: missing place"); return -1; }
    let n = p.nodes[node];
    if n.kind == N_UNARY && n.integer == T_MUL { return cc_expr(p, f, n.left); }
    if n.kind == N_NAME { return cc_symbol_ref(p, f, n.symbol, node); }
    if n.kind == N_MEMBER {
        let base = cc_base(p, f, n.left); if base < 0 || n.symbol < 0 { cc_fail(p, node, "c: member has no checked field"); return -1; }
        let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", base); cc_text(f.out, ",");
        cc_number(f.out, p.nodes[n.symbol].integer); cc_text(f.out, ");\n"); return ref;
    }
    if n.kind == N_INDEX {
        let base = cc_base(p, f, n.left); let index = cc_to(p, f, n.right, TYPE_I64);
        var array = p.nodes[n.left].type_id; if cc_kind(p, array) == TY_REF { array = p.types[array].element; }
        if cc_kind(p, array) != TY_ARRAY && cc_kind(p, array) != TY_SLICE { cc_fail(p, node, "c: indexing a non-array"); return -1; }
        let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_element_at("); cc_id(f.out, "g_v", base); cc_text(f.out, ",");
        cc_array_args(p, f.out, array); cc_text(f.out, ","); cc_id(f.out, "g_v", index); cc_text(f.out, ",0,"); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return ref;
    }
    let value = cc_expr(p, f, node); if value < 0 { return -1; } return cc_temporary_ref(f, value);
}
recursive fn cc_convert(p: Program&, f: CcBody&, value: i64, from: i64, to: i64, node: i64, clone: bool = false) -> i64 {
    if value < 0 || to < 0 { return -1; }
    if from == to {
        if clone && cc_needs_clone(p, to, 0) {
            let result = cc_temp(p, f, to); cc_set(f, result); cc_id(f.out, "g_clone_", to); cc_text(f.out, "("); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); return result;
        }
        return value;
    }
    let a = cc_kind(p, from); let b = cc_kind(p, to);
    if a == TY_REF && b == TY_BOOL && (p.types[from].flags & TF_OPTIONAL) != 0 {
        let result = cc_temp(p, f, to); cc_set(f, result); cc_text(f.out, "!!"); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); return result;
    }
    if a == TY_REF && b != TY_REF {
        let inner = p.types[from].element; let loaded = cc_load(p, f, value, inner); return cc_convert(p, f, loaded, inner, to, node, clone);
    }
    let result = cc_temp(p, f, to); if result < 0 { return -1; }
    if (a == TY_INT || a == TY_FLOAT || a == TY_BOOL) && (b == TY_INT || b == TY_FLOAT || b == TY_BOOL) {
        cc_set(f, result);
        if b == TY_BOOL { cc_text(f.out, "!!"); cc_id(f.out, "g_v", value); }
        else {
            cc_text(f.out, "("); cc_type(f.out, to); cc_text(f.out, ")");
            if a == TY_FLOAT && b == TY_INT { cc_text(f.out, "g_float_wrap("); cc_id(f.out, "g_v", value); cc_text(f.out, ")"); }
            else { cc_id(f.out, "g_v", value); }
        }
        cc_text(f.out, ";\n"); return result;
    }
    if a == TY_REF && b == TY_REF || a == TY_FN && b == TY_FN || a == TY_SLICE && b == TY_SLICE {
        cc_set(f, result); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); return result;
    }
    if (a == TY_ARRAY || a == TY_SLICE) && b == TY_ARRAY {
        cc_array_convert(p, f, value, from, to, result, node); return result;
    }
    if a == TY_STRUCT && b == TY_ENUM && p.types[from].pool >= 0 &&
       p.types[p.types[from].pool].declaration == p.types[to].declaration {
        cc_text(f.out, "g_write_length(&"); cc_id(f.out, "g_v", result); cc_text(f.out, ",");
        cc_number(f.out, p.types[to].length_storage); cc_text(f.out, ",");
        cc_number(f.out, p.nodes[p.types[from].declaration].integer); cc_text(f.out, ");\nmemcpy(((unsigned char*)&");
        cc_id(f.out, "g_v", result); cc_text(f.out, ")+"); cc_number(f.out, p.types[to].length_storage);
        cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",sizeof("); cc_type(f.out, from); cc_text(f.out, "));\n"); return result;
    }
    if a == TY_TUPLE && b == TY_TUPLE {
        var source = p.types[from].first; var destination = p.types[to].first; var index = 0;
        while source >= 0 && destination >= 0 {
            let source_type = p.nodes[source].type_id; let destination_type = p.nodes[destination].type_id;
            let part = cc_temp(p, f, source_type); cc_set(f, part);
            cc_id(f.out, "g_v", value); cc_id(f.out, ".f", index); cc_text(f.out, ";\n");
            let adapted = cc_convert(p, f, part, source_type, destination_type, node, clone);
            if adapted >= 0 {
                cc_id(f.out, "g_v", result); cc_id(f.out, ".f", index); cc_text(f.out, "=");
                cc_id(f.out, "g_v", adapted); cc_text(f.out, ";\n");
            }
            source = p.nodes[source].next; destination = p.nodes[destination].next; index++;
        }
        if source >= 0 || destination >= 0 { cc_fail(p, node, "c: tuple conversion arity mismatch"); }
        return result;
    }
    if cc_aggregate(p, from) && cc_aggregate(p, to) && p.types[from].size == p.types[to].size {
        cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_v", result); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",sizeof("); cc_type(f.out, to); cc_text(f.out, "));\n");
        if clone && cc_needs_clone(p, to, 0) {
            cc_set(f, result); cc_id(f.out, "g_clone_", to); cc_text(f.out, "("); cc_id(f.out, "g_v", result); cc_text(f.out, ");\n");
        }
        return result;
    }
    cc_conversion_fail(p, node, from, to); return -1;
}
recursive fn cc_array_convert(p: Program&, f: CcBody&, value: i64, from: i64, to: i64, result: i64, node: i64) {
    let source = cc_temporary_ref(f, value); let destination = cc_temporary_ref(f, result);
    let count = cc_temp(p, f, TYPE_I64); cc_set(f, count);
    cc_text(f.out, "g_len("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, from, false); cc_text(f.out, ");\n");
    if p.types[to].array_kind == A_FIXED {
        cc_text(f.out, "if("); cc_id(f.out, "g_v", count); cc_text(f.out, "!="); cc_number(f.out, p.types[to].count); cc_text(f.out, ")g_panic(\"fixed array length mismatch\");\n");
    } else {
        cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", destination); cc_text(f.out, ","); cc_array_args(p, f.out, to);
        cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ");g_set_len("); cc_id(f.out, "g_v", destination);
        cc_text(f.out, ","); cc_array_args(p, f.out, to, false); cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ");\n");
    }
    let source_element = p.types[from].element; let destination_element = p.types[to].element;
    if source_element == destination_element && !cc_needs_clone(p, destination_element, 0) {
        cc_text(f.out, "if("); cc_id(f.out, "g_v", count); cc_text(f.out, ")memcpy(g_address(g_element("); cc_id(f.out, "g_v", destination);
        cc_text(f.out, ","); cc_array_args(p, f.out, to); cc_text(f.out, ",0,1)),g_address(g_element("); cc_id(f.out, "g_v", source);
        cc_text(f.out, ","); cc_array_args(p, f.out, from); cc_text(f.out, ",0,1)),(size_t)"); cc_id(f.out, "g_v", count);
        cc_text(f.out, "*"); cc_number(f.out, p.types[destination_element].size); cc_text(f.out, ");\n"); return;
    }
    let counter = f.serial; f.serial++;
    cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", count);
    cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){\n");
    let loaded = cc_temp(p, f, source_element); cc_set(f, loaded); cc_id(f.out, "g_load_", source_element); cc_text(f.out, "(g_element(");
    cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, from); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0));\n");
    let copied = cc_convert(p, f, loaded, source_element, destination_element, node, true);
    cc_id(f.out, "g_store_", destination_element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", destination); cc_text(f.out, ","); cc_array_args(p, f.out, to);
    cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0),"); cc_id(f.out, "g_v", copied); cc_text(f.out, ");}\n");
}
recursive fn cc_to(p: Program&, f: CcBody&, node: i64, to: i64, clone: bool = false) -> i64 {
    if node < 0 { cc_fail(p, node, "c: missing value"); return -1; }
    let from = p.nodes[node].type_id;
    if cc_kind(p, to) == TY_REF && cc_owner(p, p.types[to].element) {
        var location: i64 = -1;
        if cc_kind(p, from) == TY_REF { location = cc_expr(p, f, node); }
        else { location = cc_place(p, f, node); }
        let owner = cc_ref_temp(f); cc_set(f, owner); cc_text(f.out, "g_owner("); cc_id(f.out, "g_v", location); cc_text(f.out, ");\n"); return owner;
    }
    if cc_kind(p, to) == TY_REF && cc_kind(p, from) != TY_REF { return cc_place(p, f, node); }
    var source_array = from;
    while cc_kind(p, source_array) == TY_REF { source_array = p.types[source_array].element; }
    if cc_kind(p, source_array) == TY_ARRAY && cc_kind(p, to) == TY_SLICE {
        var base = cc_base(p, f, node); var current = from;
        while cc_kind(p, current) == TY_REF && cc_kind(p, p.types[current].element) == TY_REF {
            current = p.types[current].element; base = cc_load(p, f, base, current);
        }
        let result = cc_temp(p, f, to); cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, source_array); cc_text(f.out, ");\n"); return result;
    }
    let value = cc_expr(p, f, node); return cc_convert(p, f, value, from, to, node, clone);
}
fn cc_bytes(out: u8[>..]&, text: const u8[:]) {
    cc_text(out, "\"");
    for c in text {
        // Fixed-width octal escapes cannot consume a following hex digit.
        cc_text(out, "\\"); out.push((48 + ((c as i64 >> 6) & 7)) as u8);
        out.push((48 + ((c as i64 >> 3) & 7)) as u8); out.push((48 + ((c as i64) & 7)) as u8);
    }
    cc_text(out, "\"");
}
fn cc_function_result(p: Program&, function: i64) -> i64 {
    let type_id = p.nodes[function].type_id;
    if cc_kind(p, type_id) != TY_FN { return TYPE_VOID; } return p.types[type_id].element;
}
fn cc_function_type(p: Program&, out: u8[>..]&, type_id: i64) {
    cc_type(out, p.types[type_id].element); cc_text(out, " (*)(GClosure*");
    var param = p.types[type_id].first;
    while param >= 0 { cc_text(out, ","); cc_type(out, p.nodes[param].type_id); param = p.nodes[param].next; }
    cc_text(out, ")");
}
recursive fn cc_closure(p: Program&, f: CcBody&, function: i64, type_id: i64) -> i64 {
    let result = cc_temp(p, f, type_id); var count = 0; var capture = p.nodes[function].captures;
    while capture >= 0 { count++; capture = p.nodes[capture].next; }
    cc_set(f, result); cc_text(f.out, "g_closure((void*)"); cc_id(f.out, "g_fn", function); cc_text(f.out, ","); cc_number(f.out, count); cc_text(f.out, ");\n");
    capture = p.nodes[function].captures; var index = 0;
    while capture >= 0 {
        let ref = cc_symbol_ref(p, f, p.nodes[capture].symbol, function);
        cc_id(f.out, "g_v", result); cc_text(f.out, "->captures["); cc_number(f.out, index); cc_text(f.out, "]="); cc_id(f.out, "g_v", ref); cc_text(f.out, ";\n");
        index++; capture = p.nodes[capture].next;
    }
    return result;
}

fn cc_concrete(p: Program&, id: i64) -> bool {
    let kind = cc_kind(p, id);
    if kind == TY_UNKNOWN || kind == TY_GENERIC || kind == TY_NAME { return false; }
    let t = p.types[id];
    if kind == TY_ARRAY || kind == TY_SLICE || kind == TY_REF {
        let element = cc_kind(p, t.element);
        if element == TY_UNKNOWN || element == TY_GENERIC || element == TY_NAME { return false; }
    }
    if kind == TY_STRUCT || kind == TY_ENUM {
        if t.declaration < 0 { return false; }
        var field = p.nodes[t.declaration].first;
        while field >= 0 {
            if p.nodes[field].kind == N_VARIANT && p.nodes[field].type_id < 0 { return false; }
            if p.nodes[field].kind == N_FIELD && (p.nodes[field].flags & F_PAD) == 0 {
                let fk = cc_kind(p, p.nodes[field].type_id);
                if fk == TY_UNKNOWN || fk == TY_GENERIC || fk == TY_NAME { return false; }
            }
            field = p.nodes[field].next;
        }
    }
    return true;
}
fn cc_use_type(p: Program&, used: bool[:], work: i64[>..]&, type_id: i64) {
    if type_id < 0 || type_id >= used.len || used[type_id] { return; }
    used[type_id] = true; work.push(type_id);
}
fn cc_used_types(p: Program&, used: bool[:], work: i64[>..]&) {
    // Lowering introduces scalar counters, predicates, and conversion temps.
    for type_id in 0..TYPE_STRING + 1 { cc_use_type(p, used, work, type_id); }
    for n in p.nodes {
        if (n.flags & F_CHECKED) == 0 { continue; }
        if n.kind >= N_INTEGER && n.kind <= N_EXPR_STMT || n.kind == N_BLOCK || n.kind == N_FUNCTION_VALUE || n.kind == N_VARIABLE || n.kind == N_TUPLE {
            cc_use_type(p, used, work, n.type_id);
        }
    }
    for symbol in p.symbols {
        if (symbol.flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 &&
           (symbol.owner < 0 || cc_emittable(p, symbol.owner)) {
            cc_use_type(p, used, work, symbol.type_id);
        }
    }
    for n, id in p.nodes { if cc_emittable(p, id) { cc_use_type(p, used, work, n.type_id); } }
    var at = 0;
    while at < work.len {
        let t = p.types[work[at]]; at++;
        if t.kind == TY_REF || t.kind == TY_ARRAY || t.kind == TY_SLICE || t.kind == TY_FN { cc_use_type(p, used, work, t.element); }
        var field = -1;
        if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE || t.kind == TY_FN { field = t.first; }
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 { cc_use_type(p, used, work, p.nodes[field].type_id); }
            field = p.nodes[field].next;
        }
    }
}
fn cc_emit_types(p: Program&, out: u8[>..]&, used: const bool[:]) {
    for t, id in p.types {
        if !used[id] || !cc_concrete(p, id) { continue; }
        cc_text(out, "typedef ");
        if t.kind == TY_VOID { cc_text(out, "void"); }
        else if t.kind == TY_BOOL { cc_text(out, "uint8_t"); }
        else if t.kind == TY_INT {
            if (t.flags & TF_UNSIGNED) != 0 { cc_text(out, "uint"); } else { cc_text(out, "int"); }
            cc_number(out, t.count); cc_text(out, "_t");
        } else if t.kind == TY_FLOAT {
            if t.count == 32 { cc_text(out, "float"); } else { cc_text(out, "double"); }
        } else if t.kind == TY_REF { cc_text(out, "GRef"); }
        else if t.kind == TY_FN { cc_text(out, "GClosure*"); }
        else if t.kind == TY_SLICE { cc_text(out, "GSlice"); }
        else if t.kind == TY_TUPLE { cc_id(out, "struct g_tuple", id); }
        else { cc_text(out, "struct { unsigned char data["); cc_number(out, t.size); cc_text(out, "]; }"); }
        cc_text(out, " "); cc_type(out, id); cc_text(out, ";\n");
    }
    for t, id in p.types {
        if !used[id] || t.kind != TY_TUPLE { continue; }
        cc_id(out, "struct g_tuple", id); cc_text(out, " {"); var field = t.first; var index = 0;
        while field >= 0 {
            cc_type(out, p.nodes[field].type_id); cc_text(out, " "); cc_id(out, "f", index); cc_text(out, ";");
            index++; field = p.nodes[field].next;
        }
        cc_text(out, "};\n");
    }
    for t, id in p.types {
        if !used[id] || !cc_concrete(p, id) || t.kind == TY_VOID { continue; }
        cc_text(out, "static "); cc_type(out, id); cc_id(out, " g_clone_", id); cc_text(out, "("); cc_type(out, id); cc_text(out, " v);\n");
        cc_text(out, "static int "); cc_id(out, "g_equal_", id); cc_text(out, "("); cc_type(out, id); cc_text(out, " a,"); cc_type(out, id); cc_text(out, " b);\n");
        cc_text(out, "static void "); cc_id(out, "g_print_", id); cc_text(out, "(GArray *out,"); cc_type(out, id); cc_text(out, " v);\n");
        cc_text(out, "static void "); cc_id(out, "g_nested_", id); cc_text(out, "(GArray *out,"); cc_type(out, id); cc_text(out, " v);\n");
        cc_text(out, "static "); cc_type(out, id); cc_id(out, " g_load_", id); cc_text(out, "(GRef p) {"); cc_type(out, id);
        cc_text(out, " v; memcpy(&v,g_address(p),sizeof v); return v;}\nstatic void "); cc_id(out, "g_store_", id); cc_text(out, "(GRef p,"); cc_type(out, id);
        cc_text(out, " v) { memcpy(g_address(p),&v,sizeof v); }\n");
    }
}
fn cc_clone_field(p: Program&, out: u8[>..]&, field: i64) {
    let n = p.nodes[field]; if (n.flags & F_PAD) != 0 || !cc_needs_clone(p, n.type_id, 0) { return; }
    cc_id(out, "g_store_", n.type_id); cc_text(out, "(g_offset(g_ref(&v),"); cc_number(out, n.integer); cc_text(out, "),");
    cc_id(out, "g_clone_", n.type_id); cc_text(out, "("); cc_id(out, "g_load_", n.type_id); cc_text(out, "(g_offset(g_ref(&v),"); cc_number(out, n.integer); cc_text(out, "))));\n");
}
fn cc_emit_clone(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !cc_concrete(p, id) || t.kind == TY_VOID { return; }
    cc_text(out, "static "); cc_type(out, id); cc_id(out, " g_clone_", id); cc_text(out, "("); cc_type(out, id); cc_text(out, " v) {\n");
    if !cc_needs_clone(p, id, 0) { cc_text(out, "return v;}\n"); return; }
    if t.kind == TY_ARRAY {
        let element = t.element;
        cc_text(out, "GRef src=g_ref(&v); int64_t n=g_len(src,"); cc_array_args(p, out, id, false); cc_text(out, ");\n");
        if cc_owner(p, id) {
            cc_text(out, "GArray old; memcpy(&old,&v,sizeof old); GArray fresh={0}; fresh.len=old.len; fresh.cap=old.cap; fresh.data=g_alloc((size_t)fresh.cap*");
            cc_number(out, p.types[element].size); cc_text(out, "); memcpy(&v,&fresh,sizeof fresh);\n");
            cc_text(out, "src=g_ref(&old);\n");
            if !cc_needs_clone(p, element, 0) {
                cc_text(out, "if(old.len)memcpy(fresh.data,old.data,(size_t)old.len*"); cc_number(out, p.types[element].size); cc_text(out, ");return v;}\n"); return;
            }
        }
        cc_text(out, "GRef dst=g_ref(&v); for(int64_t i=0;i<n;i++) {\n");
        cc_id(out, "g_store_", element); cc_text(out, "(g_element(dst,"); cc_array_args(p, out, id); cc_text(out, ",i,0),");
        cc_id(out, "g_clone_", element); cc_text(out, "("); cc_id(out, "g_load_", element); cc_text(out, "(g_element(src,"); cc_array_args(p, out, id); cc_text(out, ",i,0)))); }\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first;
        while field >= 0 { cc_clone_field(p, out, field); field = p.nodes[field].next; }
    } else if t.kind == TY_ENUM && t.declaration >= 0 {
        cc_text(out, "switch(g_read_length(&v,"); cc_number(out, t.length_storage); cc_text(out, ")) {\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            cc_text(out, "case "); cc_number(out, p.nodes[variant].integer); cc_text(out, ":{\n"); let payload = p.nodes[variant].type_id;
            cc_type(out, payload); cc_text(out, " body;memcpy(&body,((unsigned char*)&v)+"); cc_number(out, t.length_storage); cc_text(out, ",sizeof body);body=");
            cc_id(out, "g_clone_", payload); cc_text(out, "(body);memcpy(((unsigned char*)&v)+"); cc_number(out, t.length_storage); cc_text(out, ",&body,sizeof body);break;}\n"); variant = p.nodes[variant].next;
        }
        cc_text(out, "default:g_panic(\"corrupt ADT tag\"); }\n");
    } else if t.kind == TY_TUPLE {
        var part = t.first; var index = 0;
        while part >= 0 {
            cc_id(out, "v.f", index); cc_text(out, "="); cc_id(out, "g_clone_", p.nodes[part].type_id); cc_text(out, "("); cc_id(out, "v.f", index); cc_text(out, ");\n");
            index++; part = p.nodes[part].next;
        }
    }
    cc_text(out, "return v;}\n");
}
fn cc_print_field(p: Program&, out: u8[>..]&, field: i64, separator: bool) {
    let n = p.nodes[field]; if (n.flags & F_PAD) != 0 { return; }
    if separator { cc_text(out, "g_print_text(out,\", \");\n"); }
    cc_id(out, "g_nested_", n.type_id); cc_text(out, "(out,"); cc_id(out, "g_load_", n.type_id); cc_text(out, "(g_offset(g_ref(&v),"); cc_number(out, n.integer); cc_text(out, ")));\n");
}
fn cc_emit_print(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !cc_concrete(p, id) || t.kind == TY_VOID { return; }
    cc_text(out, "static void "); cc_id(out, "g_print_", id); cc_text(out, "(GArray *out,"); cc_type(out, id); cc_text(out, " v) {\n");
    if t.kind == TY_INT || t.kind == TY_FLOAT || t.kind == TY_BOOL {
        cc_text(out, "unsigned char b[128]; int64_t n=");
        if t.kind == TY_BOOL { cc_text(out, "gs_fmt_bool(b,v)"); }
        else if t.kind == TY_FLOAT && t.count == 32 { cc_text(out, "gs_fmt_f32(b,v)"); }
        else if t.kind == TY_FLOAT { cc_text(out, "gs_fmt_f64(b,v)"); }
        else if (t.flags & TF_UNSIGNED) != 0 { cc_text(out, "gs_fmt_u64(b,v)"); }
        else { cc_text(out, "gs_fmt_i64(b,v)"); }
        cc_text(out, ";g_print_bytes(out,b,n);\n");
    } else if t.kind == TY_REF && cc_kind(p, t.element) == TY_VOID {
        cc_text(out, "g_print_text(out,\"null\");\n");
    } else if t.kind == TY_REF {
        cc_text(out, "if(!v) g_print_text(out,\"null\"); else "); cc_id(out, "g_print_", t.element); cc_text(out, "(out,"); cc_id(out, "g_load_", t.element); cc_text(out, "(v));\n");
    } else if t.kind == TY_FN { cc_text(out, "g_print_text(out,\"fn\");\n"); }
    else if t.kind == TY_ARRAY || t.kind == TY_SLICE {
        cc_text(out, "GRef r=g_ref(&v); int64_t n=g_len(r,"); cc_array_args(p, out, id, false); cc_text(out, ");\n");
        let bytes = cc_kind(p, t.element) == TY_INT && p.types[t.element].count == 8 && (p.types[t.element].flags & TF_UNSIGNED) != 0;
        if !bytes { cc_text(out, "g_print_text(out,\"[\");\n"); }
        cc_text(out, "for(int64_t i=0;i<n;i++) {\n");
        if !bytes { cc_text(out, "if(i)g_print_text(out,\", \");\n"); }
        if bytes {
            cc_text(out, "g_print_bytes(out,g_address(g_element(r,"); cc_array_args(p, out, id); cc_text(out, ",i,0)),1);\n");
        } else {
            cc_id(out, "g_nested_", t.element); cc_text(out, "(out,"); cc_id(out, "g_load_", t.element); cc_text(out, "(g_element(r,"); cc_array_args(p, out, id); cc_text(out, ",i,0)));\n");
        }
        cc_text(out, "}\n"); if !bytes { cc_text(out, "g_print_text(out,\"]\");\n"); }
    } else if t.kind == TY_STRUCT && t.declaration >= 0 && p.nodes[t.declaration].kind == N_VARIANT && p.nodes[t.declaration].first < 0 && t.pool >= 0 {
        cc_text(out, "g_print_text(out,"); cc_bytes(out, token_text(p, p.nodes[p.types[t.pool].declaration].token)); cc_text(out, ");g_print_text(out,\".\");g_print_text(out,");
        cc_bytes(out, token_text(p, p.nodes[t.declaration].token)); cc_text(out, ");\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        var name: u8[>..] = [];
        if p.nodes[t.declaration].kind == N_VARIANT { name.append(token_text(p, p.nodes[t.declaration].token)); }
        else { render_type_name(p, id, name, 0, false); }
        cc_text(out, "g_print_text(out,"); cc_bytes(out, name); cc_text(out, ");g_print_text(out,\" { \");\n");
        var field = p.nodes[t.declaration].first; var separator = false;
        while field >= 0 { cc_print_field(p, out, field, separator); if (p.nodes[field].flags & F_PAD) == 0 { separator = true; } field = p.nodes[field].next; }
        cc_text(out, "g_print_text(out,\" }\");\n");
    } else if t.kind == TY_ENUM && t.declaration >= 0 {
        cc_text(out, "switch(g_read_length(&v,"); cc_number(out, t.length_storage); cc_text(out, ")) {\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            cc_text(out, "case "); cc_number(out, p.nodes[variant].integer); cc_text(out, ":\n");
            var field = p.nodes[variant].first;
            if field < 0 {
                cc_text(out, "g_print_text(out,"); cc_bytes(out, token_text(p, p.nodes[t.declaration].token)); cc_text(out, ");g_print_text(out,\".\");g_print_text(out,");
                cc_bytes(out, token_text(p, p.nodes[variant].token)); cc_text(out, ");\n");
            }
            if field >= 0 {
                cc_text(out, "{\n"); let payload = p.nodes[variant].type_id; cc_type(out, payload);
                cc_text(out, " body;memcpy(&body,((unsigned char*)&v)+"); cc_number(out, t.length_storage); cc_text(out, ",sizeof body);");
                cc_id(out, "g_print_", payload); cc_text(out, "(out,body); }\n");
            }
            cc_text(out, "break;\n"); variant = p.nodes[variant].next;
        }
        cc_text(out, "default:g_panic(\"corrupt ADT tag\");}\n");
    } else if t.kind == TY_TUPLE {
        var part = t.first; var index = 0;
        while part >= 0 {
            if index > 0 { cc_text(out, "g_print_text(out,\", \");\n"); }
            cc_id(out, "g_print_", p.nodes[part].type_id); cc_text(out, "(out,"); cc_id(out, "v.f", index); cc_text(out, ");\n");
            index++; part = p.nodes[part].next;
        }
    }
    cc_text(out, "}\n");
}

recursive fn cc_default(p: Program&, f: CcBody&, type_id: i64) -> i64 {
    let result = cc_temp(p, f, type_id); if result < 0 { return -1; }
    let t = p.types[type_id];
    if t.kind == TY_ARRAY && t.array_kind == A_FIXED {
        let counter = f.serial; f.serial++;
        cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_number(f.out, t.count); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++) {\n");
        let element = cc_default(p, f, t.element); cc_id(f.out, "g_store_", t.element); cc_text(f.out, "(g_element(g_ref(&"); cc_id(f.out, "g_v", result); cc_text(f.out, "),"); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0),"); cc_id(f.out, "g_v", element); cc_text(f.out, ");}\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first;
        while field >= 0 {
            let n = p.nodes[field];
            if (n.flags & F_PAD) == 0 {
                var value: i64 = -1;
                if n.right >= 0 { value = cc_to(p, f, n.right, n.type_id, true); } else { value = cc_default(p, f, n.type_id); }
                let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_offset(g_ref(&"); cc_id(f.out, "g_v", result); cc_text(f.out, "),"); cc_number(f.out, n.integer); cc_text(f.out, ");\n"); cc_store(f, ref, value, n.type_id);
            }
            field = n.next;
        }
    }
    return result;
}
fn cc_binary_operator(out: u8[>..]&, op: i64) -> bool {
    if op == T_PLUS { cc_text(out, "+"); } else if op == T_MINUS { cc_text(out, "-"); }
    else if op == T_MUL { cc_text(out, "*"); } else if op == T_DIV { cc_text(out, "/"); }
    else if op == T_MOD { cc_text(out, "%"); } else if op == T_BITAND { cc_text(out, "&"); }
    else if op == T_BITOR { cc_text(out, "|"); } else if op == T_XOR { cc_text(out, "^"); }
    else if op == T_SHL { cc_text(out, "<<"); } else if op == T_SHR { cc_text(out, ">>"); }
    else if op == T_EQ || op == T_DOTEQ { cc_text(out, "=="); } else if op == T_NEQ || op == T_DOTNEQ { cc_text(out, "!="); }
    else if op == T_LT { cc_text(out, "<"); } else if op == T_GT { cc_text(out, ">"); }
    else if op == T_LTEQ { cc_text(out, "<="); } else if op == T_GTEQ { cc_text(out, ">="); }
    else { return false; } return true;
}
fn cc_binary_values(p: Program&, f: CcBody&, op: i64, left: i64, right: i64, operand: i64, result_type: i64, node: i64) -> i64 {
    let result = cc_temp(p, f, result_type); if result < 0 { return -1; }
    let t = p.types[operand]; cc_set(f, result);
    if op == T_DOTEQ || op == T_DOTNEQ {
        cc_text(f.out, "(g_nullable_address("); cc_id(f.out, "g_v", left); cc_text(f.out, ")"); cc_binary_operator(f.out, op); cc_text(f.out, "g_nullable_address("); cc_id(f.out, "g_v", right); cc_text(f.out, "))");
    } else if cc_aggregate(p, operand) || t.kind == TY_SLICE {
        if op != T_EQ && op != T_NEQ { cc_text(f.out, "0"); cc_fail(p, node, "c: aggregate operator needs a resolved overload"); }
        else {
            if op == T_NEQ { cc_text(f.out, "!"); }
            cc_id(f.out, "g_equal_", operand); cc_text(f.out, "("); cc_id(f.out, "g_v", left); cc_text(f.out, ","); cc_id(f.out, "g_v", right); cc_text(f.out, ")");
        }
    } else if p.debug && t.kind == TY_INT && (t.flags & TF_UNSIGNED) == 0 &&
              (op == T_PLUS || op == T_MINUS || op == T_MUL || op == T_DIV) {
        cc_text(f.out, "g_checked_binary("); cc_id(f.out, "g_v", left); cc_text(f.out, ","); cc_id(f.out, "g_v", right);
        cc_text(f.out, ","); cc_number(f.out, t.count); cc_text(f.out, ","); cc_number(f.out, op); cc_text(f.out, ",");
        cc_location(p, f.out, node); cc_text(f.out, ")");
    } else if (op == T_DIV || op == T_MOD) && t.kind == TY_INT {
        if (t.flags & TF_UNSIGNED) != 0 { if op == T_DIV { cc_text(f.out, "g_udiv("); } else { cc_text(f.out, "g_umod("); } }
        else { if op == T_DIV { cc_text(f.out, "g_div("); } else { cc_text(f.out, "g_mod("); } }
        cc_id(f.out, "g_v", left); cc_text(f.out, ","); cc_id(f.out, "g_v", right); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ")");
    } else if op == T_MOD && t.kind == TY_FLOAT {
        cc_text(f.out, "fmod("); cc_id(f.out, "g_v", left); cc_text(f.out, ","); cc_id(f.out, "g_v", right); cc_text(f.out, ")");
    } else {
        let wrap = t.kind == TY_INT && (op == T_PLUS || op == T_MINUS || op == T_MUL || op == T_SHL);
        cc_text(f.out, "("); cc_type(f.out, result_type); cc_text(f.out, ")(");
        if wrap { cc_text(f.out, "(uint64_t)"); }
        cc_id(f.out, "g_v", left);
        if !cc_binary_operator(f.out, op) { cc_fail(p, node, "c: unknown binary operator"); }
        if wrap { cc_text(f.out, "(uint64_t)"); }
        if op == T_SHL || op == T_SHR { cc_text(f.out, "("); }
        cc_id(f.out, "g_v", right);
        if op == T_SHL || op == T_SHR { cc_text(f.out, "&"); cc_number(f.out, t.count - 1); cc_text(f.out, ")"); }
        cc_text(f.out, ")");
    }
    cc_text(f.out, ";\n"); return result;
}
recursive fn cc_binary(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node];
    if (n.integer == T_EQ || n.integer == T_NEQ) &&
       (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) {
        let left = cc_expr(p, f, n.left); let right = cc_expr(p, f, n.right);
        var op = T_DOTEQ; if n.integer == T_NEQ { op = T_DOTNEQ; }
        return cc_binary_values(p, f, op, left, right, p.nodes[n.left].type_id, TYPE_BOOL, node);
    }
    if n.integer == T_ANDAND || n.integer == T_OROR {
        let result = cc_to(p, f, n.left, TYPE_BOOL); cc_text(f.out, "if(");
        if n.integer == T_OROR { cc_text(f.out, "!"); } cc_id(f.out, "g_v", result); cc_text(f.out, ") {\n");
        let right = cc_to(p, f, n.right, TYPE_BOOL); cc_set(f, result); cc_id(f.out, "g_v", right); cc_text(f.out, ";}\n"); return result;
    }
    var operand = p.nodes[n.left].type_id;
    if cc_kind(p, operand) == TY_REF && n.integer != T_DOTEQ && n.integer != T_DOTNEQ { operand = p.types[operand].element; }
    if cc_kind(p, n.aux) == TY_INT || cc_kind(p, n.aux) == TY_FLOAT || cc_kind(p, n.aux) == TY_BOOL { operand = n.aux; }
    let left = cc_to(p, f, n.left, operand); let right = cc_to(p, f, n.right, operand);
    return cc_binary_values(p, f, n.integer, left, right, operand, n.type_id, node);
}
recursive fn cc_block(p: Program&, f: CcBody&, node: i64, destination: i64 = -1) -> i64 {
    let n = p.nodes[node]; var result = destination;
    if result < 0 && n.type_id >= 0 && cc_kind(p, n.type_id) != TY_VOID { result = cc_temp(p, f, n.type_id); }
    var early = false; var label = -1;
    if (n.flags & F_EARLY) != 0 {
        early = true; label = f.serial; f.serial++;
        f.exits.push(CcExit { node: node, done: label, result: result, type_id: n.type_id });
    }
    cc_text(f.out, "{\n"); var child = n.first;
    while child >= 0 {
        let kind = p.nodes[child].kind;
        let terminates = kind == N_RETURN || kind == N_BREAK || kind == N_CONTINUE;
        if !terminates && p.nodes[child].next < 0 && (p.nodes[child].flags & F_TAIL) != 0 && result >= 0 {
            let value = cc_to(p, f, child, n.type_id, true);
            if value < 0 { cc_fail(p, child, "c: block result has no value"); }
            else { cc_set(f, result); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); }
        } else { cc_expr(p, f, child); }
        child = p.nodes[child].next;
    }
    cc_text(f.out, "}\n");
    if early { f.exits.pop(); cc_id(f.out, "g_label", label); cc_text(f.out, ":;\n"); }
    return result;
}
recursive fn cc_values(p: Program&, f: CcBody&, first: i64, type_id: i64) -> i64 {
    if cc_kind(p, type_id) == TY_VOID {
        var effect = first;
        while effect >= 0 { cc_expr(p, f, effect); effect = p.nodes[effect].next; }
        return -1;
    }
    if cc_kind(p, type_id) != TY_TUPLE { return cc_to(p, f, first, type_id, true); }
    let result = cc_temp(p, f, type_id); var part = p.types[type_id].first; var value = first; var index = 0;
    while part >= 0 && value >= 0 {
        let v = cc_to(p, f, value, p.nodes[part].type_id, true);
        if v < 0 { return -1; }
        cc_id(f.out, "g_v", result); cc_id(f.out, ".f", index); cc_text(f.out, "="); cc_id(f.out, "g_v", v); cc_text(f.out, ";\n");
        index++; part = p.nodes[part].next; value = p.nodes[value].next;
    }
    if part >= 0 || value >= 0 { cc_fail(p, first, "c: return value arity mismatch"); } return result;
}
recursive fn cc_return(p: Program&, f: CcBody&, node: i64) {
    let n = p.nodes[node]; var target = f.function;
    if n.symbol >= 0 && n.symbol < p.symbols.len { target = p.symbols[n.symbol].node; }
    let type_id = cc_function_result(p, target); let result = cc_values(p, f, n.first, type_id);
    if target == f.function {
        if result >= 0 { cc_text(f.out, "g_result="); cc_id(f.out, "g_v", result); cc_text(f.out, ";\n"); }
        cc_text(f.out, "goto g_return;\n");
    } else {
        cc_text(f.out, "g_throw("); cc_number(f.out, target); cc_text(f.out, ",");
        if result >= 0 { cc_text(f.out, "&"); cc_id(f.out, "g_v", result); cc_text(f.out, ",sizeof("); cc_type(f.out, type_id); cc_text(f.out, ")"); }
        else { cc_text(f.out, "NULL,0"); } cc_text(f.out, ");\n");
    }
}
recursive fn cc_loop_path(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_NAME { return true; }
    if n.kind == N_MEMBER || n.kind == N_UNARY && n.integer == T_MUL { return cc_loop_path(p, n.left); }
    return false;
}
recursive fn cc_loop(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; var result = -1;
    if n.type_id >= 0 { result = cc_temp(p, f, n.type_id); }
    let done = f.serial; f.serial++;
    let again = f.serial; f.serial++;
    f.exits.push(CcExit { node: node, done: done, again: again, result: result, type_id: n.type_id });
    cc_text(f.out, "{\n");
    if n.kind == N_FOR {
        let binding = n.first; let index_binding = p.nodes[binding].next;
        let iterable = p.nodes[n.left]; var counter = -1; var end = -1; var base = -1; var array = iterable.type_id;
        if iterable.kind == N_RANGE {
            counter = cc_to(p, f, iterable.left, TYPE_I64); end = cc_to(p, f, iterable.right, TYPE_I64);
        } else if cc_kind(p, array) == TY_INT {
            end = cc_to(p, f, n.left, TYPE_I64); counter = cc_temp(p, f, TYPE_I64);
        } else {
            if cc_kind(p, array) == TY_REF { array = p.types[array].element; }
            base = cc_base(p, f, n.left); counter = cc_temp(p, f, TYPE_I64); end = cc_temp(p, f, TYPE_I64);
            cc_set(f, end); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, ");\n");
        }
        if base >= 0 {
            cc_text(f.out, "for(;;) {\n");
            if cc_loop_path(p, n.left) { base = cc_base(p, f, n.left); }
            cc_set(f, end); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, ");\n");
            cc_text(f.out, "if("); cc_id(f.out, "g_v", counter); cc_text(f.out, ">="); cc_id(f.out, "g_v", end); cc_text(f.out, ")break;\n");
        } else {
            cc_text(f.out, "for(; "); cc_id(f.out, "g_v", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", end); cc_text(f.out, ";"); cc_id(f.out, "g_v", counter); cc_text(f.out, "++) {\n");
        }
        if base >= 0 {
            let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array); cc_text(f.out, ","); cc_id(f.out, "g_v", counter); cc_text(f.out, ",0);\n");
            var value = ref;
            if (p.nodes[binding].flags & F_REFERENCE) == 0 || cc_kind(p, p.types[array].element) == TY_REF { value = cc_load(p, f, ref, p.types[array].element); }
            cc_id(f.out, "g_s", p.nodes[binding].symbol); cc_text(f.out, "="); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n");
        } else {
            cc_id(f.out, "g_s", p.nodes[binding].symbol); cc_text(f.out, "="); cc_id(f.out, "g_v", counter); cc_text(f.out, ";\n");
        }
        if index_binding >= 0 {
            cc_id(f.out, "g_s", p.nodes[index_binding].symbol); cc_text(f.out, "="); cc_id(f.out, "g_v", counter); cc_text(f.out, ";\n");
        }
        cc_expr(p, f, n.right); cc_id(f.out, "g_label", again); cc_text(f.out, ":;\n");
        if base >= 0 { cc_id(f.out, "g_v", counter); cc_text(f.out, "++;\n"); }
        cc_text(f.out, "}\n");
    } else {
        cc_text(f.out, "for(;;) {\n");
        if n.kind == N_WHILE {
            let condition = cc_to(p, f, n.left, TYPE_BOOL); cc_text(f.out, "if(!"); cc_id(f.out, "g_v", condition); cc_text(f.out, ") break;\n");
        }
        cc_expr(p, f, n.right); cc_id(f.out, "g_label", again); cc_text(f.out, ":;\n}\n");
    }
    cc_id(f.out, "g_label", done); cc_text(f.out, ":;}\n"); f.exits.pop(); return result;
}
recursive fn cc_call(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node];
    if (n.flags & F_DISPATCH) != 0 { return cc_dispatch(p, f, node); }
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 { return cc_builtin(p, f, node, p.symbols[n.symbol].index); }
    var function: i64 = -1; var callable = p.nodes[n.left].type_id; var closure: i64 = -1;
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { function = p.symbols[n.symbol].node; callable = p.symbols[n.symbol].type_id; }
    if function >= 0 {
        if p.nodes[function].captures >= 0 { closure = cc_closure(p, f, function, callable); }
    } else { closure = cc_expr(p, f, n.left); }
    if cc_kind(p, callable) != TY_FN { cc_fail(p, node, "c: call lacks a checked function signature"); return -1; }
    let args_start = f.work.len; var args_count = 0; var param = p.types[callable].first; var arg = n.first;
    while arg >= 0 { f.work.push(-1); args_count++; arg = p.nodes[arg].next; }
    arg = n.first; var ordinal = 0;
    while param >= 0 && arg >= 0 {
        let value = cc_to(p, f, arg, p.nodes[param].type_id, true);
        if value < 0 { return -1; }
        f.work[args_start + ordinal] = value;
        ordinal++; param = p.nodes[param].next; arg = p.nodes[arg].next;
    }
    if param >= 0 || arg >= 0 { cc_fail(p, node, "c: checked call argument arity mismatch"); return -1; }
    let natural_type = p.types[callable].element;
    let result = cc_temp(p, f, natural_type);
    if result >= 0 { cc_set(f, result); }
    if function >= 0 { cc_id(f.out, "g_fn", function); }
    else { cc_text(f.out, "(("); cc_function_type(p, f.out, callable); cc_text(f.out, ")"); cc_id(f.out, "g_v", closure); cc_text(f.out, "->function)"); }
    cc_text(f.out, "(");
    if closure >= 0 { cc_id(f.out, "g_v", closure); } else { cc_text(f.out, "NULL"); }
    for i in 0..args_count { cc_text(f.out, ","); cc_id(f.out, "g_v", f.work[args_start + i]); } cc_text(f.out, ");\n");
    return cc_convert(p, f, result, natural_type, n.type_id, node);
}

recursive fn cc_dispatch(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node];
    if n.symbol < 0 || n.third < 0 || n.aux < 0 { cc_fail(p, node, "c: case dispatch lacks checked arms"); return -1; }
    let signature = p.symbols[n.symbol].type_id;
    let args_start = f.work.len; var count = 0; var argument = n.first;
    while argument >= 0 { f.work.push(-1); count++; argument = p.nodes[argument].next; }
    var parameter = p.types[signature].first; var ordinal = 0;
    var original = -1; var snapshot = -1; var enum_type = -1; argument = n.first;
    while argument >= 0 && parameter >= 0 {
        if ordinal == n.aux {
            enum_type = p.nodes[argument].type_id;
            while cc_kind(p, enum_type) == TY_REF { enum_type = p.types[enum_type].element; }
            if cc_kind(p, enum_type) != TY_ENUM { cc_fail(p, node, "c: dispatch argument is not an enum"); return -1; }
            original = cc_base(p, f, argument);
            let value = cc_load(p, f, original, enum_type);
            let copied = cc_convert(p, f, value, enum_type, enum_type, argument, true);
            snapshot = cc_temporary_ref(f, copied);
        } else {
            let value = cc_to(p, f, argument, p.nodes[parameter].type_id, true);
            f.work[args_start + ordinal] = value;
        }
        ordinal++; argument = p.nodes[argument].next; parameter = p.nodes[parameter].next;
    }
    if argument >= 0 || parameter >= 0 || snapshot < 0 { cc_fail(p, node, "c: dispatch argument arity mismatch"); return -1; }
    let result = cc_temp(p, f, n.type_id); var tag_source = snapshot;
    if (p.types[enum_type].flags & F_VARIABLE_MODE) != 0 { tag_source = original; }
    cc_text(f.out, "switch(g_read_length(g_address("); cc_id(f.out, "g_v", tag_source); cc_text(f.out, "),"); cc_number(f.out, p.types[enum_type].length_storage); cc_text(f.out, ")){\n");
    var arm = n.third;
    while arm >= 0 {
        let selected = p.nodes[arm]; let function = p.symbols[selected.symbol].node;
        let callable = p.symbols[selected.symbol].type_id;
        var dispatch_parameter = p.types[callable].first;
        for i in 0..n.aux { dispatch_parameter = p.nodes[dispatch_parameter].next; }
        let dispatch_type = p.nodes[dispatch_parameter].type_id;
        cc_text(f.out, "case "); cc_number(f.out, selected.integer); cc_text(f.out, ":{\n");
        let payload_ref = cc_ref_temp(f); cc_set(f, payload_ref); cc_text(f.out, "g_offset(");
        if cc_kind(p, dispatch_type) == TY_REF { cc_id(f.out, "g_v", original); }
        else { cc_id(f.out, "g_v", snapshot); }
        cc_text(f.out, ","); cc_number(f.out, p.types[enum_type].length_storage); cc_text(f.out, ");\n");
        var payload = payload_ref;
        if cc_kind(p, dispatch_type) != TY_REF { payload = cc_load(p, f, payload_ref, dispatch_type); }
        f.work[args_start + n.aux] = payload;
        var closure = -1;
        if p.nodes[function].captures >= 0 { closure = cc_closure(p, f, function, callable); }
        let natural_type = p.types[callable].element; let natural = cc_temp(p, f, natural_type);
        if natural >= 0 { cc_set(f, natural); }
        cc_id(f.out, "g_fn", function); cc_text(f.out, "(");
        if closure >= 0 { cc_id(f.out, "g_v", closure); } else { cc_text(f.out, "NULL"); }
        for i in 0..count { cc_text(f.out, ","); cc_id(f.out, "g_v", f.work[args_start + i]); }
        cc_text(f.out, ");\n");
        let adapted = cc_convert(p, f, natural, natural_type, n.type_id, node);
        if result >= 0 && adapted >= 0 { cc_set(f, result); cc_id(f.out, "g_v", adapted); cc_text(f.out, ";\n"); }
        cc_text(f.out, "break;}\n"); arm = selected.next;
    }
    cc_text(f.out, "default:g_panic(\"corrupt ADT tag\");}\n"); return result;
}

recursive fn cc_array(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; let t = p.types[n.type_id]; let result = cc_temp(p, f, n.type_id);
    var base: i64 = -1;
    if t.kind == TY_SLICE {
        let raw = f.serial; f.serial++; cc_id(f.out, "GArray g_array", raw); cc_text(f.out, "={0};\n");
        base = cc_ref_temp(f); cc_set(f, base); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_array", raw); cc_text(f.out, ");\n");
    } else { base = cc_temporary_ref(f, result); }
    var length = -1; var elements = 0; var child = n.first;
    while child >= 0 { elements++; child = p.nodes[child].next; }
    if n.right >= 0 { length = cc_to(p, f, n.right, TYPE_I64); }
    else { length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_number(f.out, elements); cc_text(f.out, ";\n"); }
    var capacity = length;
    if n.third >= 0 { capacity = cc_to(p, f, n.third, TYPE_I64); }
    if length < 0 || capacity < 0 { return -1; }
    if cc_owner(p, n.type_id) || t.kind == TY_SLICE {
        cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ",");
        cc_id(f.out, "g_v", capacity);
        cc_text(f.out, ");\n");
    }
    if t.array_kind != A_FIXED {
        cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
    }
    if n.right >= 0 && n.first >= 0 {
        let value = cc_to(p, f, n.first, t.element, true); if value < 0 { return -1; }
        let counter = f.serial; f.serial++;
        cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", length); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){\n");
        cc_id(f.out, "g_store_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0),"); cc_id(f.out, "g_clone_", t.element); cc_text(f.out, "("); cc_id(f.out, "g_v", value); cc_text(f.out, "));}\n");
    } else {
        child = n.first; var index = 0;
        while child >= 0 {
            let value = cc_to(p, f, child, t.element, true);
            if value < 0 { return -1; }
            cc_id(f.out, "g_store_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ","); cc_number(f.out, index); cc_text(f.out, ",0),"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n");
            index++; child = p.nodes[child].next;
        }
    }
    if t.kind == TY_SLICE {
        cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ");\n");
    }
    return result;
}
recursive fn cc_record(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; let result = cc_temp(p, f, n.type_id); var base = cc_temporary_ref(f, result);
    if cc_kind(p, n.type_id) == TY_ENUM && n.symbol >= 0 && p.nodes[n.symbol].kind == N_VARIANT {
        let tag_bytes = p.types[n.type_id].length_storage;
        cc_text(f.out, "g_write_length(g_address("); cc_id(f.out, "g_v", base); cc_text(f.out, "),");
        cc_number(f.out, tag_bytes); cc_text(f.out, ","); cc_number(f.out, p.nodes[n.symbol].integer); cc_text(f.out, ");\n");
        let payload = cc_ref_temp(f); cc_set(f, payload); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", base);
        cc_text(f.out, ","); cc_number(f.out, tag_bytes); cc_text(f.out, ");\n"); base = payload;
    }
    var binding = n.first;
    while binding >= 0 {
        let field = p.nodes[binding].symbol;
        if field < 0 { cc_fail(p, binding, "c: record initializer lacks a checked field"); return -1; }
        let type_id = p.nodes[field].type_id; var value = -1;
        if p.nodes[binding].right >= 0 { value = cc_to(p, f, p.nodes[binding].right, type_id, true); }
        else { value = cc_default(p, f, type_id); }
        if value < 0 { return -1; }
        let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_number(f.out, p.nodes[field].integer); cc_text(f.out, ");\n");
        cc_store(f, ref, value, type_id); binding = p.nodes[binding].next;
    }
    return result;
}
recursive fn cc_variable(p: Program&, f: CcBody&, node: i64) {
    let n = p.nodes[node];
    if n.first < 0 {
        let destination = cc_symbol_ref(p, f, n.symbol, node); var value: i64 = -1;
        if n.right >= 0 { value = cc_to(p, f, n.right, p.symbols[n.symbol].type_id, true); }
        else { value = cc_default(p, f, p.symbols[n.symbol].type_id); }
        cc_store(f, destination, value, p.symbols[n.symbol].type_id); return;
    }
    let values_start = f.work.len; var values_count = 0; var current = n.right;
    while current >= 0 { f.work.push(-1); f.work.push(-1); values_count++; current = p.nodes[current].next; }
    current = n.right; var ordinal = 0;
    while current >= 0 {
        let value = cc_expr(p, f, current); f.work[values_start + ordinal * 2] = value;
        f.work[values_start + ordinal * 2 + 1] = p.nodes[current].type_id;
        ordinal++; current = p.nodes[current].next;
    }
    var binding = n.first; var index = 0;
    while binding >= 0 {
        let bn = p.nodes[binding]; let destination = cc_symbol_ref(p, f, bn.symbol, binding); let type_id = p.symbols[bn.symbol].type_id;
        if values_count == 1 && cc_kind(p, f.work[values_start + (0) * 2 + 1]) == TY_TUPLE {
            let value = cc_temp(p, f, type_id); cc_set(f, value); cc_id(f.out, "g_v", f.work[values_start + (0) * 2]); cc_id(f.out, ".f", index); cc_text(f.out, ";\n"); cc_store(f, destination, value, type_id);
        } else if index < values_count {
            let value = cc_convert(p, f, f.work[values_start + (index) * 2], f.work[values_start + (index) * 2 + 1], type_id, binding, true); cc_store(f, destination, value, type_id);
        } else { let value = cc_default(p, f, type_id); cc_store(f, destination, value, type_id); }
        index++; binding = bn.next;
    }
}
recursive fn cc_assignment(p: Program&, f: CcBody&, node: i64) {
    let n = p.nodes[node];
    if n.kind == N_MULTI_ASSIGN {
        let value = cc_expr(p, f, n.right); var target = n.first; var index = 0;
        while target >= 0 {
            var type_id = p.nodes[target].type_id; var ref = cc_place(p, f, target);
            if cc_kind(p, type_id) == TY_REF { ref = cc_expr(p, f, target); type_id = p.types[type_id].element; }
            let part = cc_temp(p, f, type_id);
            cc_set(f, part); cc_id(f.out, "g_v", value); cc_id(f.out, ".f", index); cc_text(f.out, ";\n"); cc_store(f, ref, part, type_id);
            index++; target = p.nodes[target].next;
        }
        return;
    }
    var type_id = p.nodes[n.left].type_id; var ref = cc_place(p, f, n.left);
    if n.integer != T_DOTASSIGN && cc_kind(p, type_id) == TY_REF { ref = cc_expr(p, f, n.left); type_id = p.types[type_id].element; }
    if n.integer == T_ASSIGN || n.integer == T_DOTASSIGN {
        let value = cc_to(p, f, n.right, type_id, true); cc_store(f, ref, value, type_id); return;
    }
    let old = cc_load(p, f, ref, type_id); var right: i64 = -1; var op = n.integer;
    if op == T_INC || op == T_DEC {
        right = cc_temp(p, f, type_id); cc_set(f, right); cc_text(f.out, "1;\n");
        if op == T_INC { op = T_PLUS; } else { op = T_MINUS; }
    } else {
        right = cc_to(p, f, n.right, type_id);
        if op == T_PLUSEQ { op = T_PLUS; } else if op == T_MINUSEQ { op = T_MINUS; }
        else if op == T_MULEQ { op = T_MUL; } else if op == T_DIVEQ { op = T_DIV; }
        else if op == T_MODEQ { op = T_MOD; } else if op == T_ANDEQ { op = T_BITAND; }
        else if op == T_OREQ { op = T_BITOR; } else if op == T_XOREQ { op = T_XOR; }
        else if op == T_SHLEQ { op = T_SHL; } else if op == T_SHREQ { op = T_SHR; }
    }
    let value = cc_binary_values(p, f, op, old, right, type_id, type_id, node); cc_store(f, ref, value, type_id);
}
recursive fn cc_builtin(p: Program&, f: CcBody&, node: i64, builtin: i64) -> i64 {
    let n = p.nodes[node]; let args_start = f.work.len; var args_count = 0; var arg = n.first;
    while arg >= 0 { f.work.push(arg); args_count++; arg = p.nodes[arg].next; }
    if builtin == 14 { return cc_default(p, f, n.type_id); }
    if builtin == 15 { return cc_to(p, f, f.work[args_start + 0], n.type_id, true); }
    if builtin == 0 || builtin == 1 || builtin == 2 {
        var output = -1; var start = 0; var builder = -1; var limited = -1;
        let raw = f.serial; f.serial++;
        if builtin == 0 {
            cc_id(f.out, "GArray g_output", raw); cc_text(f.out, "={0};\n");
            builder = cc_ref_temp(f); cc_set(f, builder); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_output", raw); cc_text(f.out, ");\n");
        }
        if builtin == 1 { output = cc_temp(p, f, n.type_id); builder = cc_temporary_ref(f, output); }
        if builtin == 2 {
            let receiver = f.work[args_start]; builder = cc_base(p, f, receiver); start = 1;
            var array = p.nodes[receiver].type_id; while cc_kind(p, array) == TY_REF { array = p.types[array].element; }
            if cc_kind(p, array) == TY_ARRAY && p.types[array].array_kind == A_LIMITED { limited = array; }
        }
        cc_id(f.out, "GArray g_builder", raw); cc_text(f.out, ";\n");
        for i in start..args_count {
            let value = cc_expr(p, f, f.work[args_start + i]); if value < 0 { return -1; }
            if limited >= 0 { cc_id(f.out, "g_builder", raw); cc_text(f.out, "=(GArray){0};\n"); }
            else {
                cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_builder", raw); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", builder); cc_text(f.out, "),sizeof(GArray));\n");
            }
            cc_id(f.out, "g_print_", p.nodes[f.work[args_start + i]].type_id); cc_text(f.out, "(&"); cc_id(f.out, "g_builder", raw);
            cc_text(f.out, ","); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n");
            if limited >= 0 {
                cc_text(f.out, "g_append_bytes("); cc_id(f.out, "g_v", builder); cc_text(f.out, ","); cc_array_args(p, f.out, limited, false);
                cc_text(f.out, ","); cc_id(f.out, "g_builder", raw); cc_text(f.out, ".data,"); cc_id(f.out, "g_builder", raw); cc_text(f.out, ".len);\n");
            } else {
                cc_text(f.out, "memcpy(g_address("); cc_id(f.out, "g_v", builder); cc_text(f.out, "),&"); cc_id(f.out, "g_builder", raw); cc_text(f.out, ",sizeof(GArray));\n");
            }
        }
        if builtin == 0 {
            cc_text(f.out, "flockfile(stdout);g_print_bytes(NULL,"); cc_id(f.out, "g_output", raw); cc_text(f.out, ".data,");
            cc_id(f.out, "g_output", raw); cc_text(f.out, ".len);g_print_text(NULL,\"\\n\");funlockfile(stdout);\n");
        }
        return output;
    }
    if builtin == 3 {
        let condition = cc_to(p, f, f.work[args_start + 0], TYPE_BOOL); cc_text(f.out, "if(!"); cc_id(f.out, "g_v", condition);
        cc_text(f.out, ")g_debug_fail("); cc_location(p, f.out, node); cc_text(f.out, ",\"assert failed\");\n"); return -1;
    }
    if builtin == 4 {
        let value = cc_expr(p, f, f.work[args_start + 0]); let message = f.serial; f.serial++;
        cc_id(f.out, "GArray g_message", message); cc_text(f.out, "={0};\n");
        cc_id(f.out, "g_print_", p.nodes[f.work[args_start + 0]].type_id); cc_text(f.out, "(&"); cc_id(f.out, "g_message", message);
        cc_text(f.out, ","); cc_id(f.out, "g_v", value); cc_text(f.out, ");g_abort_value("); cc_id(f.out, "g_message", message);
        cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return -1;
    }
    if builtin == 5 { let value = cc_to(p, f, f.work[args_start + 0], TYPE_I32); cc_text(f.out, "exit("); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); return -1; }
    if builtin == 6 {
        let result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_text(f.out, "sysconf(_SC_NPROCESSORS_ONLN);\n"); return result;
    }
    if builtin >= 7 && builtin <= 13 { cc_fail(p, node, "c: thread and queue lowering requires native runtime integration"); return -1; }
    if builtin == 19 || builtin == 20 { cc_fail(p, node, "c: embed builtin must be folded by the source driver"); return -1; }
    if builtin == 18 { cc_fail(p, node, "c: from_bytes requires verified packed-image decoding"); return -1; }
    if args_count == 0 { cc_fail(p, node, "c: builtin has no receiver"); return -1; }
    let receiver = f.work[args_start + 0]; var type_id = p.nodes[receiver].type_id;
    if cc_kind(p, type_id) == TY_REF { type_id = p.types[type_id].element; }
    let base = cc_base(p, f, receiver); let t = p.types[type_id];
    if builtin == 16 || builtin == 17 {
        if t.kind != TY_ARRAY && t.kind != TY_SLICE { cc_fail(p, node, "c: byte image requires an array"); return -1; }
        let result = cc_temp(p, f, n.type_id);
        if cc_kind(p, n.type_id) != TY_SLICE { cc_fail(p, node, "c: owned byte serialization requires image construction"); return -1; }
        cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ");\n");
        cc_id(f.out, "g_v", result); cc_text(f.out, ".len*="); cc_number(f.out, p.types[t.element].size); cc_text(f.out, ";\n"); return result;
    }
    if builtin == 21 || builtin == 22 {
        let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        if builtin == 21 { cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); }
        else { cc_text(f.out, "g_cap("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_number(f.out, cc_array_kind(p, type_id)); cc_text(f.out, ","); cc_number(f.out, t.count); }
        cc_text(f.out, ");\n"); return result;
    }
    if builtin == 23 {
        let value = cc_base(p, f, f.work[args_start + 1]); let result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_text(f.out, "-1;\n");
        let counter = f.serial; f.serial++;
        cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){if(g_address(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0))==g_address("); cc_id(f.out, "g_v", value); cc_text(f.out, ")){"); cc_set(f, result); cc_id(f.out, "g_i", counter); cc_text(f.out, ";break;}}\n"); return result;
    }
    if builtin == 24 || builtin == 30 || builtin == 31 {
        if builtin >= 30 { cc_fail(p, node, "c: reusable slot allocation needs freelist image lowering"); return -1; }
        let value = cc_to(p, f, f.work[args_start + 1], t.element, true); let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        cc_text(f.out, "g_push("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); return result;
    }
    if builtin == 25 {
        let source = cc_base(p, f, f.work[args_start + 1]); var source_type = p.nodes[f.work[args_start + 1]].type_id;
        if cc_kind(p, source_type) == TY_REF { source_type = p.types[source_type].element; }
        let count = cc_temp(p, f, TYPE_I64); cc_set(f, count); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, source_type, false); cc_text(f.out, ");\n");
        if !cc_needs_clone(p, t.element, 0) {
            let old = cc_temp(p, f, TYPE_I64); cc_set(f, old); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");\n");
            cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, "+"); cc_id(f.out, "g_v", count); cc_text(f.out, ");\n");
            cc_text(f.out, "if("); cc_id(f.out, "g_v", count); cc_text(f.out, ")memmove(g_address(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, ",1)),g_address(g_element("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, source_type); cc_text(f.out, ",0,1)),(size_t)"); cc_id(f.out, "g_v", count); cc_text(f.out, "*"); cc_number(f.out, p.types[t.element].size); cc_text(f.out, ");\n");
            cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, "+"); cc_id(f.out, "g_v", count); cc_text(f.out, ");\n"); return -1;
        }
        let counter = f.serial; f.serial++;
        cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", count); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){\n");
        let value = cc_temp(p, f, t.element); cc_set(f, value); cc_id(f.out, "g_clone_", t.element); cc_text(f.out, "("); cc_id(f.out, "g_load_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, source_type); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0)));\n");
        cc_text(f.out, "g_push("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ");}\n"); return -1;
    }
    if builtin >= 26 && builtin <= 29 {
        var requested = -1; var fill = -1;
        if builtin == 27 || builtin == 28 {
            requested = cc_to(p, f, f.work[args_start + 1], TYPE_I64); if requested < 0 { return -1; }
        }
        if builtin == 28 {
            cc_text(f.out, "if("); cc_id(f.out, "g_v", requested); cc_text(f.out, "<0)g_panic_at(\"resize to a negative length\","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
            if args_count >= 3 { fill = cc_to(p, f, f.work[args_start + 2], t.element, true); if fill < 0 { return -1; } }
        }
        let old = cc_temp(p, f, TYPE_I64); cc_set(f, old); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");\n");
        var length = cc_temp(p, f, TYPE_I64); var result = -1;
        if builtin == 26 {
            cc_text(f.out, "if(!"); cc_id(f.out, "g_v", old); cc_text(f.out, ")g_panic(\"pop on empty array\");\n");
            cc_set(f, length); cc_id(f.out, "g_v", old); cc_text(f.out, "-1;\n");
            result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_id(f.out, "g_clone_", t.element); cc_text(f.out, "("); cc_id(f.out, "g_load_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ",0)));\n");
        } else if builtin == 29 { cc_set(f, length); cc_text(f.out, "0;\n"); }
        else {
            if builtin == 27 {
                cc_text(f.out, "if("); cc_id(f.out, "g_v", requested); cc_text(f.out, "<0||"); cc_id(f.out, "g_v", requested); cc_text(f.out, ">");
                cc_id(f.out, "g_v", old); cc_text(f.out, ")g_panic_at(\"pop_n count negative or beyond the array's length\","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
            }
            cc_set(f, length);
            if builtin == 27 { cc_id(f.out, "g_v", old); cc_text(f.out, "-"); } cc_id(f.out, "g_v", requested); cc_text(f.out, ";\n");
        }
        cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, "<0)g_panic_at(\"resize to a negative length\","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
        if builtin == 28 {
            cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
            if args_count >= 3 {
                let counter = f.serial; f.serial++;
                cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
                cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "="); cc_id(f.out, "g_v", old); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", length); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){"); cc_id(f.out, "g_store_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0),"); cc_id(f.out, "g_clone_", t.element); cc_text(f.out, "("); cc_id(f.out, "g_v", fill); cc_text(f.out, "));}\n");
            } else { cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, ">"); cc_id(f.out, "g_v", old); cc_text(f.out, ")g_panic(\"resize growth requires fill\");\n"); }
        } else { cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, ">"); cc_id(f.out, "g_v", old); cc_text(f.out, ")g_panic(\"pop count exceeds length\");\n"); }
        cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n"); return result;
    }
    cc_fail(p, node, "c: reusable slice/slot builtin requires pool runtime integration"); return -1;
}

recursive fn cc_match(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; var source_type = p.nodes[n.left].type_id;
    while cc_kind(p, source_type) == TY_REF { source_type = p.types[source_type].element; }
    let source = cc_to(p, f, n.left, source_type); let result = cc_temp(p, f, n.type_id); let done = f.serial; f.serial++;
    let enum_match = cc_kind(p, source_type) == TY_ENUM;
    var arm = n.first;
    while arm >= 0 {
        let a = p.nodes[arm]; let pattern = p.nodes[a.left]; cc_text(f.out, "if(");
        if (pattern.flags & F_DEFAULT) != 0 { cc_text(f.out, "1"); }
        else {
            var item = pattern.first; var separator = false;
            while item >= 0 {
                if separator { cc_text(f.out, "||"); } cc_text(f.out, "("); let pat = p.nodes[item];
                if enum_match {
                    cc_text(f.out, "g_read_length(&"); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_number(f.out, p.types[source_type].length_storage); cc_text(f.out, ")=="); cc_number(f.out, pat.integer);
                } else if pat.kind == N_RANGE {
                    cc_id(f.out, "g_v", source); cc_text(f.out, ">="); cc_number(f.out, p.nodes[pat.left].integer); cc_text(f.out, "&&"); cc_id(f.out, "g_v", source);
                    if (pat.flags & F_INCLUSIVE) != 0 { cc_text(f.out, "<="); } else { cc_text(f.out, "<"); }
                    cc_number(f.out, p.nodes[pat.right].integer);
                } else { cc_id(f.out, "g_v", source); cc_text(f.out, "==UINT64_C("); f.out.format(pat.integer as! u64); cc_text(f.out, ")"); }
                cc_text(f.out, ")"); separator = true; item = pat.next;
            }
        }
        cc_text(f.out, "){\n");
        if pattern.left >= 0 {
            let binder = p.nodes[pattern.left];
            if (binder.flags & F_REFERENCE) != 0 {
                let place = cc_base(p, f, n.left); cc_id(f.out, "g_s", binder.symbol); cc_text(f.out, "=g_offset("); cc_id(f.out, "g_v", place); cc_text(f.out, ","); cc_number(f.out, p.types[source_type].length_storage); cc_text(f.out, ");\n");
            } else {
                cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_s", binder.symbol); cc_text(f.out, ",((unsigned char*)&"); cc_id(f.out, "g_v", source); cc_text(f.out, ")+"); cc_number(f.out, p.types[source_type].length_storage); cc_text(f.out, ",sizeof("); cc_type(f.out, binder.type_id); cc_text(f.out, "));\n");
            }
        }
        if a.third >= 0 { let condition_guard = cc_to(p, f, a.third, TYPE_BOOL); cc_text(f.out, "if("); cc_id(f.out, "g_v", condition_guard); cc_text(f.out, "){\n"); }
        if result >= 0 {
            let body = cc_to(p, f, a.right, n.type_id, true); cc_set(f, result); cc_id(f.out, "g_v", body); cc_text(f.out, ";\n");
        } else { cc_expr(p, f, a.right); }
        cc_id(f.out, "goto g_label", done); cc_text(f.out, ";\n"); if a.third >= 0 { cc_text(f.out, "}\n"); }
        cc_text(f.out, "}\n"); arm = a.next;
    }
    cc_text(f.out, "g_panic(\"non-exhaustive match\");\n"); cc_id(f.out, "g_label", done); cc_text(f.out, ":;\n"); return result;
}
recursive fn cc_expr(p: Program&, f: CcBody&, node: i64) -> i64 {
    if node < 0 { return -1; }
    let n = p.nodes[node];
    if n.kind == N_INTEGER || n.kind == N_BOOL || n.kind == N_NULL {
        let result = cc_temp(p, f, n.type_id); if result < 0 { return -1; } cc_set(f, result);
        if n.kind == N_NULL { cc_text(f.out, "0"); }
        else { cc_text(f.out, "("); cc_type(f.out, n.type_id); cc_text(f.out, ")UINT64_C("); f.out.format(n.integer as! u64); cc_text(f.out, ")"); }
        cc_text(f.out, ";\n"); return result;
    }
    if n.kind == N_FLOAT {
        let result = cc_temp(p, f, n.type_id); let values: f64[1] = [n.float_value]; let bytes = bytes_of(values);
        cc_set(f, result);
        if n.float_value != n.float_value { cc_text(f.out, "NAN"); }
        else if n.float_value > 1.7976931348623157e308 { cc_text(f.out, "INFINITY"); }
        else {
            cc_text(f.out, "g_float_literal(UINT64_C("); var bits: u64 = 0;
            for byte, i in bytes { bits |= byte as u64 << (i * 8); } f.out.format(bits); cc_text(f.out, "))");
        }
        cc_text(f.out, ";\n"); return result;
    }
    if n.kind == N_STRING {
        let result = cc_temp(p, f, n.type_id); let token = p.tokens[n.token];
        if cc_kind(p, n.type_id) == TY_SLICE {
            cc_set(f, result); cc_text(f.out, "(GSlice){g_ref((void*)"); cc_bytes(f.out, p.text[token.text_start..token.text_start + token.text_len]); cc_text(f.out, "),"); cc_number(f.out, token.text_len); cc_text(f.out, "};\n");
        } else if cc_kind(p, n.type_id) == TY_ARRAY {
            let base = cc_temporary_ref(f, result);
            if cc_owner(p, n.type_id) {
                cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, n.type_id); cc_text(f.out, ","); cc_number(f.out, token.text_len); cc_text(f.out, ");\n");
            }
            if p.types[n.type_id].array_kind != A_FIXED {
                cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, n.type_id, false); cc_text(f.out, ","); cc_number(f.out, token.text_len); cc_text(f.out, ");\n");
            }
            cc_text(f.out, "memcpy(g_address(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, n.type_id); cc_text(f.out, ",0,1)),"); cc_bytes(f.out, p.text[token.text_start..token.text_start + token.text_len]); cc_text(f.out, ","); cc_number(f.out, token.text_len); cc_text(f.out, ");\n");
        } else { cc_fail(p, node, "c: string literal has a non-byte-array destination"); }
        return result;
    }
    if n.kind == N_NAME {
        if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { return cc_closure(p, f, p.symbols[n.symbol].node, n.type_id); }
        let ref = cc_symbol_ref(p, f, n.symbol, node); return cc_load(p, f, ref, n.type_id);
    }
    if n.kind == N_MEMBER || n.kind == N_INDEX { let ref = cc_place(p, f, node); return cc_load(p, f, ref, n.type_id); }
    if n.kind == N_UNARY {
        if n.integer == T_BITAND { return cc_place(p, f, n.left); }
        if n.integer == T_MUL { let ref = cc_expr(p, f, n.left); return cc_load(p, f, ref, n.type_id); }
        let operand = cc_to(p, f, n.left, p.nodes[n.left].type_id); let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        if n.integer == T_NOT { cc_text(f.out, "!"); }
        else if n.integer == T_BITNOT { cc_text(f.out, "~"); }
        else if n.integer == T_MINUS {
            if p.debug && cc_kind(p, n.type_id) == TY_INT && (p.types[n.type_id].flags & TF_UNSIGNED) == 0 {
                cc_text(f.out, "g_checked_neg("); cc_id(f.out, "g_v", operand); cc_text(f.out, ",");
                cc_number(f.out, p.types[n.type_id].count); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return result;
            }
            if cc_kind(p, n.type_id) == TY_INT { cc_text(f.out, "("); cc_type(f.out, n.type_id); cc_text(f.out, ")(UINT64_C(0)-(uint64_t)"); cc_id(f.out, "g_v", operand); cc_text(f.out, ");\n"); return result; }
            cc_text(f.out, "-");
        } else { cc_fail(p, node, "c: unknown unary operator"); }
        cc_id(f.out, "g_v", operand); cc_text(f.out, ";\n"); return result;
    }
    if n.kind == N_BINARY { return cc_binary(p, f, node); }
    if n.kind == N_CAST { return cc_cast(p, f, node); }
    if n.kind == N_CALL { return cc_call(p, f, node); }
    if n.kind == N_BLOCK { return cc_block(p, f, node); }
    if n.kind == N_ARRAY || n.kind == N_FILL { return cc_array(p, f, node); }
    if n.kind == N_RECORD { return cc_record(p, f, node); }
    if n.kind == N_TUPLE { return cc_values(p, f, n.first, n.type_id); }
    if n.kind == N_FUNCTION_VALUE { return cc_closure(p, f, node, n.type_id); }
    if n.kind == N_SLICE {
        let base = cc_base(p, f, n.left); var array = p.nodes[n.left].type_id;
        if cc_kind(p, array) == TY_REF { array = p.types[array].element; }
        let length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, ");\n");
        var low = cc_temp(p, f, TYPE_I64); var high = length;
        if n.right >= 0 { low = cc_to(p, f, n.right, TYPE_I64); }
        if n.third >= 0 { high = cc_to(p, f, n.third, TYPE_I64); }
        if (n.flags & F_FROM_END) != 0 { cc_set(f, low); cc_id(f.out, "g_v", length); cc_text(f.out, "-"); cc_id(f.out, "g_v", low); cc_text(f.out, ";\n"); }
        if (n.flags & F_TO_END) != 0 { cc_set(f, high); cc_id(f.out, "g_v", length); cc_text(f.out, "-"); cc_id(f.out, "g_v", high); cc_text(f.out, ";\n"); }
        cc_text(f.out, "if("); cc_id(f.out, "g_v", low); cc_text(f.out, "<0||"); cc_id(f.out, "g_v", high); cc_text(f.out, "<"); cc_id(f.out, "g_v", low); cc_text(f.out, "||"); cc_id(f.out, "g_v", high); cc_text(f.out, ">"); cc_id(f.out, "g_v", length); cc_text(f.out, ")g_panic(\"slice bounds out of range\");\n");
        let result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_text(f.out, "(GSlice){g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array); cc_text(f.out, ","); cc_id(f.out, "g_v", low); cc_text(f.out, ",1),"); cc_id(f.out, "g_v", high); cc_text(f.out, "-"); cc_id(f.out, "g_v", low); cc_text(f.out, "};\n"); return result;
    }
    if n.kind == N_IF {
        let condition = cc_to(p, f, n.left, TYPE_BOOL); let result = cc_temp(p, f, n.type_id);
        cc_text(f.out, "if("); cc_id(f.out, "g_v", condition); cc_text(f.out, "){\n");
        if result >= 0 {
            let value = cc_to(p, f, n.right, n.type_id, true);
            if value >= 0 { cc_set(f, result); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); }
        }
        else { cc_expr(p, f, n.right); } cc_text(f.out, "}else{\n");
        if n.third >= 0 {
            if result >= 0 {
                let value = cc_to(p, f, n.third, n.type_id, true);
                if value >= 0 { cc_set(f, result); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); }
            }
            else { cc_expr(p, f, n.third); }
        }
        cc_text(f.out, "}\n"); return result;
    }
    if n.kind == N_LOOP || n.kind == N_FOR || n.kind == N_WHILE { return cc_loop(p, f, node); }
    if n.kind == N_MATCH { return cc_match(p, f, node); }
    if n.kind == N_RETURN { cc_return(p, f, node); return -1; }
    if n.kind == N_BREAK || n.kind == N_CONTINUE {
        var index = f.exits.len - 1;
        while index >= 0 && (n.symbol >= 0 && f.exits[index].node != n.symbol ||
              n.kind == N_CONTINUE && f.exits[index].again < 0) { index--; }
        if index < 0 { cc_fail(p, node, "c: jump has no enclosing loop or early block"); return -1; }
        let exit = f.exits[index];
        if n.left >= 0 && exit.result >= 0 {
            var value = -1;
            if cc_kind(p, exit.type_id) == TY_TUPLE && p.nodes[n.left].next >= 0 { value = cc_values(p, f, n.left, exit.type_id); }
            else { value = cc_to(p, f, n.left, exit.type_id, true); }
            if value >= 0 { cc_set(f, exit.result); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); }
        } else if n.left >= 0 { cc_values(p, f, n.left, TYPE_VOID); }
        var label = exit.done; if n.kind == N_CONTINUE { label = exit.again; }
        cc_id(f.out, "goto g_label", label); cc_text(f.out, ";\n"); return -1;
    }
    if n.kind == N_VARIABLE { cc_variable(p, f, node); return -1; }
    if n.kind == N_ASSIGN || n.kind == N_MULTI_ASSIGN { cc_assignment(p, f, node); return -1; }
    if n.kind == N_FUNCTION || n.kind == N_EMPTY { return -1; }
    if n.kind == N_EXPR_STMT { cc_expr(p, f, n.left); return -1; }
    cc_fail(p, node, "c: checked syntax has no native lowering"); return -1;
}

fn cc_param_symbol(p: Program&, function: i64, index: i64) -> i64 {
    var param = p.nodes[function].first; var at = 0;
    while param >= 0 { if at == index { return p.nodes[param].symbol; } at++; param = p.nodes[param].next; } return -1;
}
fn cc_extern_name(p: Program&, function: i64) -> u8[:] {
    let n = p.nodes[function];
    if n.integer >= 0 && n.integer < p.tokens.len && p.tokens[n.integer].kind == T_STRLIT {
        let t = p.tokens[n.integer]; return p.text[t.text_start..t.text_start + t.text_len];
    }
    return token_text(p, n.token);
}
fn cc_param(p: Program&, out: u8[>..]&, function: i64, index: i64) { cc_id(out, "g_s", cc_param_symbol(p, function, index)); }
fn cc_runtime_extern(name: const u8[:]) -> const u8[:] {
    if same_bytes(name, "gs_find_any") { return "g_find_any"; }
    if same_bytes(name, "gs_find_pair") { return "g_find_pair"; }
    if same_bytes(name, "gs_mul_add") { return "g_mul_add"; }
    if same_bytes(name, "gs_mul_addf") { return "g_mul_addf"; }
    for math_name in ["sqrt", "sqrtf", "sin", "sinf", "cos", "cosf", "tan", "tanf",
                      "asin", "asinf", "acos", "acosf", "atan", "atanf", "atan2", "atan2f",
                      "exp", "expf", "log", "logf", "log2", "log2f", "log10", "log10f", "pow", "powf"] {
        if name.len == math_name.len + 3 && same_bytes(name[0..3], "gs_") && same_bytes(name[3..], math_name) { return math_name; }
    }
    return "";
}
fn cc_emit_extern(p: Program&, out: u8[>..]&, function: i64) {
    let name = cc_extern_name(p, function); let result_type = cc_function_result(p, function);
    let value = cc_kind(p, result_type) != TY_VOID;
    if value { cc_text(out, "return "); }
    for exported, id in p.nodes {
        if id == function || (exported.flags & F_EXPORT) == 0 || !cc_emittable(p, id) { continue; }
        if !same_bytes(name, cc_extern_name(p, id)) { continue; }
        cc_id(out, "g_fn", id); cc_text(out, "(NULL");
        var param = p.nodes[function].first; var index = 0;
        while param >= 0 { cc_text(out, ","); cc_param(p, out, function, index); index++; param = p.nodes[param].next; }
        cc_text(out, ");\n"); return;
    }
    let runtime = cc_runtime_extern(name);
    if runtime.len > 0 {
        cc_text(out, runtime); cc_text(out, "(");
        var param = p.nodes[function].first; var index = 0;
        while param >= 0 {
            if index > 0 { cc_text(out, ","); }
            cc_param(p, out, function, index); index++; param = p.nodes[param].next;
        }
        cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_read_file") || same_bytes(name, "gs_os_list_dir") || same_bytes(name, "gs_os_getenv") {
        if same_bytes(name, "gs_os_read_file") { cc_text(out, "g_os_read_file("); }
        else if same_bytes(name, "gs_os_list_dir") { cc_text(out, "g_os_list("); }
        else { cc_text(out, "g_os_env("); }
        cc_param(p, out, function, 0); cc_text(out, ","); cc_param(p, out, function, 1); cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_write_file") || same_bytes(name, "gs_os_append_file") || same_bytes(name, "gs_os_write_file_atomic") {
        if same_bytes(name, "gs_os_write_file_atomic") { cc_text(out, "g_os_write_atomic("); }
        else { cc_text(out, "g_os_write_file("); }
        cc_param(p, out, function, 0); cc_text(out, ","); cc_param(p, out, function, 1);
        if same_bytes(name, "gs_os_write_file") { cc_text(out, ",\"wb\""); }
        if same_bytes(name, "gs_os_append_file") { cc_text(out, ",\"ab\""); }
        cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_file_exists") || same_bytes(name, "gs_os_is_dir") {
        cc_text(out, "g_os_kind("); cc_param(p, out, function, 0); cc_text(out, ")==");
        if same_bytes(name, "gs_os_is_dir") { cc_text(out, "2;\n"); } else { cc_text(out, "1;\n"); } return;
    }
    if same_bytes(name, "gs_os_remove_file") || same_bytes(name, "gs_os_remove_dir") || same_bytes(name, "gs_os_make_dir") {
        cc_text(out, "g_os_path_op("); cc_param(p, out, function, 0); cc_text(out, ",");
        if same_bytes(name, "gs_os_remove_file") { cc_text(out, "0"); }
        else if same_bytes(name, "gs_os_remove_dir") { cc_text(out, "1"); } else { cc_text(out, "2"); }
        cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_rename_file") {
        cc_text(out, "g_os_rename("); cc_param(p, out, function, 0); cc_text(out, ","); cc_param(p, out, function, 1); cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_read_line") || same_bytes(name, "gs_os_read_stdin") || same_bytes(name, "gs_os_resource_dir") {
        if same_bytes(name, "gs_os_read_line") { cc_text(out, "g_os_line("); }
        else if same_bytes(name, "gs_os_read_stdin") { cc_text(out, "g_os_stdin("); } else { cc_text(out, "g_os_resource("); }
        cc_param(p, out, function, 0); cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_write_stdout") || same_bytes(name, "gs_os_write_stderr") {
        cc_text(out, "fwrite(g_address("); cc_param(p, out, function, 0); cc_text(out, ".base),1,(size_t)"); cc_param(p, out, function, 0); cc_text(out, ".len,");
        if same_bytes(name, "gs_os_write_stderr") { cc_text(out, "stderr"); } else { cc_text(out, "stdout"); } cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_flush_stdout") { cc_text(out, "fflush(stdout);\n"); return; }
    if same_bytes(name, "gs_os_arg_count") { cc_text(out, "g_argc;\n"); return; }
    if same_bytes(name, "gs_os_arg") {
        cc_text(out, "g_os_arg("); cc_param(p, out, function, 0); cc_text(out, ","); cc_param(p, out, function, 1); cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_time_ns") { cc_text(out, "g_os_time(0);\n"); return; }
    if same_bytes(name, "gs_os_clock_ns") { cc_text(out, "g_os_time(1);\n"); return; }
    if same_bytes(name, "gs_os_sleep_ms") { cc_text(out, "g_os_sleep("); cc_param(p, out, function, 0); cc_text(out, ");\n"); return; }
    if same_bytes(name, "gs_os_random_u64") { cc_text(out, "g_os_random();\n"); return; }
    if same_bytes(name, "gs_trim_memory") { cc_text(out, "g_trim_memory();\n"); return; }
    if same_bytes(name, "gs_clz") || same_bytes(name, "gs_ctz") || same_bytes(name, "gs_popcount") {
        if same_bytes(name, "gs_clz") { cc_text(out, "g_clz("); }
        else if same_bytes(name, "gs_ctz") { cc_text(out, "g_ctz("); } else { cc_text(out, "__builtin_popcountll("); }
        cc_param(p, out, function, 0); cc_text(out, ");\n"); return;
    }
    // Foreign C signatures use raw pointers and raw pointer/length slices.
    // Runtime-owned builder references have a distinct ABI and are rejected.
    if value { cc_text(out, "("); cc_type(out, result_type); cc_text(out, ")"); }
    cc_text(out, "((");
    if cc_kind(p, result_type) == TY_REF { cc_text(out, "void*"); }
    else { cc_type(out, result_type); }
    cc_text(out, " (*) ("); var param = p.nodes[function].first; var index = 0;
    while param >= 0 {
        if index > 0 { cc_text(out, ","); }
        let type_id = p.nodes[param].type_id;
        if cc_kind(p, type_id) == TY_REF {
            let element = p.types[type_id].element;
            if cc_owner(p, element) { cc_fail(p, function, "c: foreign builder reference ABI requires a runtime adapter"); }
            cc_text(out, "void*");
        } else if cc_kind(p, type_id) == TY_SLICE { cc_text(out, "GForeignSlice"); }
        else { cc_type(out, type_id); }
        param = p.nodes[param].next; index++;
    }
    if index == 0 { cc_text(out, "void"); }
    cc_text(out, "))g_external(");
    if p.nodes[function].aux >= 0 && p.nodes[function].aux < p.tokens.len && p.tokens[p.nodes[function].aux].kind == T_STRLIT {
        let t = p.tokens[p.nodes[function].aux]; cc_bytes(out, p.text[t.text_start..t.text_start + t.text_len]);
    } else { cc_text(out, "NULL"); }
    cc_text(out, ","); cc_bytes(out, name); cc_text(out, "))("); param = p.nodes[function].first; index = 0;
    while param >= 0 {
        if index > 0 { cc_text(out, ","); }
        let kind = cc_kind(p, p.nodes[param].type_id);
        if kind == TY_REF { cc_text(out, "g_address("); cc_param(p, out, function, index); cc_text(out, ")"); }
        else if kind == TY_SLICE { cc_text(out, "g_foreign_slice("); cc_param(p, out, function, index); cc_text(out, ")"); }
        else { cc_param(p, out, function, index); }
        index++; param = p.nodes[param].next;
    }
    cc_text(out, ");\n");
    if cc_kind(p, result_type) == TY_REF || cc_kind(p, result_type) == TY_SLICE {
        cc_fail(p, function, "c: foreign reference return requires explicit ownership adaptation");
    }
}
fn cc_emit_signature(p: Program&, out: u8[>..]&, function: i64) {
    cc_text(out, "static "); cc_type(out, cc_function_result(p, function)); cc_id(out, " g_fn", function); cc_text(out, "(GClosure *g_env");
    var param = p.nodes[function].first;
    while param >= 0 {
        cc_text(out, ","); cc_type(out, p.nodes[param].type_id); cc_text(out, " "); cc_id(out, "g_s", p.nodes[param].symbol); param = p.nodes[param].next;
    }
    cc_text(out, ")");
}
fn cc_emit_function(p: Program&, out: u8[>..]&, function: i64) {
    let n = p.nodes[function]; cc_emit_signature(p, out, function); cc_text(out, " {\n");
    if (n.flags & F_EXTERN) != 0 { cc_emit_extern(p, out, function); cc_text(out, "}\n"); return; }
    var exits: CcExit[>..] = []; var work: i64[>..] = []; let result_type = cc_function_result(p, function);
    var f = CcBody { out: out, exits: exits, work: work, function: function, result_type: result_type };
    let returns = cc_kind(p, result_type) != TY_VOID;
    let nonlocal = (n.flags & F_NONLOCAL) != 0;
    if returns {
        if nonlocal { cc_text(out, "volatile "); }
        cc_type(out, result_type); cc_text(out, " g_result="); cc_zero_initializer(p, out, result_type); cc_text(out, ";\n");
    }
    if nonlocal {
        cc_text(out, "GReturnFrame g_frame={0};g_frame.parent=g_return_top;g_frame.function="); cc_number(out, function); cc_text(out, ";\n");
        if returns { cc_text(out, "g_frame.result=(void*)&g_result;g_frame.size=sizeof g_result;\n"); }
        cc_text(out, "g_return_top=&g_frame;if(setjmp(g_frame.jump))goto g_return;\n");
    }
    for s, symbol in p.symbols {
        if s.owner != function || (s.flags & (S_PARAMETER | S_FUNCTION | S_TYPE)) != 0 { continue; }
        if s.type_id < 0 || !cc_concrete(p, s.type_id) { cc_fail(p, s.node, "c: local variable lacks a concrete type"); continue; }
        cc_type(out, s.type_id); cc_text(out, " "); cc_id(out, "g_s", symbol); cc_text(out, "="); cc_zero_initializer(p, out, s.type_id); cc_text(out, ";\n");
    }
    if n.right >= 0 {
        let result = cc_expr(p, f, n.right);
        if returns && result >= 0 { cc_text(out, "g_result="); cc_id(out, "g_v", result); cc_text(out, ";\n"); }
    } else { cc_fail(p, function, "c: non-extern function has no body"); }
    cc_text(out, "g_return:;\n");
    if nonlocal { cc_text(out, "g_return_top=g_frame.parent;\n"); }
    if returns { cc_text(out, "return g_result;\n"); } else { cc_text(out, "return;\n"); } cc_text(out, "}\n");
}
fn cc_emit_export(p: Program&, out: u8[>..]&, function: i64) {
    let n = p.nodes[function]; if (n.flags & F_EXPORT) == 0 { return; }
    cc_type(out, cc_function_result(p, function)); cc_id(out, " g_export", function); cc_text(out, "(");
    var param = n.first; var index = 0;
    while param >= 0 {
        if index > 0 { cc_text(out, ","); } cc_type(out, p.nodes[param].type_id); cc_text(out, " "); cc_id(out, "g_s", p.nodes[param].symbol);
        param = p.nodes[param].next; index++;
    }
    if index == 0 { cc_text(out, "void"); }
    cc_text(out, ") __asm__("); cc_bytes(out, cc_extern_name(p, function)); cc_text(out, ");\n");
    cc_type(out, cc_function_result(p, function)); cc_id(out, " g_export", function); cc_text(out, "("); param = n.first; index = 0;
    while param >= 0 {
        if index > 0 { cc_text(out, ","); } cc_type(out, p.nodes[param].type_id); cc_text(out, " "); cc_id(out, "g_s", p.nodes[param].symbol);
        param = p.nodes[param].next; index++;
    }
    if index == 0 { cc_text(out, "void"); } cc_text(out, "){g_initialize();\n");
    if cc_kind(p, cc_function_result(p, function)) != TY_VOID { cc_text(out, "return "); }
    cc_id(out, "g_fn", function); cc_text(out, "(NULL"); param = n.first;
    while param >= 0 { cc_text(out, ","); cc_id(out, "g_s", p.nodes[param].symbol); param = p.nodes[param].next; }
    cc_text(out, ");}\n");
}
fn cc_emittable(p: Program&, function: i64) -> bool {
    let n = p.nodes[function];
    if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE { return false; }
    if (n.flags & F_GENERIC) != 0 || (n.flags & F_CHECKED) == 0 || n.type_id < 0 || cc_kind(p, n.type_id) != TY_FN { return false; }
    if !cc_concrete(p, p.types[n.type_id].element) { return false; }
    var param = n.first;
    while param >= 0 { if !cc_concrete(p, p.nodes[param].type_id) { return false; } param = p.nodes[param].next; }
    return true;
}
fn generate_c(p: Program&, out: u8[>..]&) {
    if p.diagnostics.len > 0 { return; }
    if p.pointer_bytes != 8 { diagnose_at(p, 0, 0, 0, "c: native layouts require pointer_bytes = 8"); return; }
    cc_collect_captures(p);
    var used: bool[>..] = []; used.resize(p.types.len, false); var type_work: i64[>..] = [];
    cc_used_types(p, used, type_work);
    let begin = out.len; cc_text(out, cc_runtime); cc_text(out, cc_runtime_extra);
    cc_text(out, "static void g_initialize(void); static int g_initialized;\n"); cc_emit_types(p, out, used);
    for t, id in p.types {
        if !used[id] { continue; }
        cc_emit_clone(p, out, id); cc_emit_equal(p, out, id); cc_emit_print(p, out, id); cc_emit_nested(p, out, id);
    }
    for n, node in p.nodes { if cc_emittable(p, node) { cc_emit_signature(p, out, node); cc_text(out, ";\n"); } }
    for s, symbol in p.symbols {
        if (s.flags & S_GLOBAL) == 0 { continue; }
        if s.type_id < 0 || !cc_concrete(p, s.type_id) { cc_fail(p, s.node, "c: global lacks a concrete type"); continue; }
        cc_text(out, "static "); cc_type(out, s.type_id); cc_text(out, " "); cc_id(out, "g_s", symbol); cc_text(out, ";\n");
    }
    for n, node in p.nodes { if cc_emittable(p, node) { cc_emit_function(p, out, node); cc_emit_export(p, out, node); } }
    cc_text(out, "static void g_initialize(void){if(g_initialized)return;g_initialized=1;\n"); var exits: CcExit[>..] = []; var work: i64[>..] = []; var f = CcBody { out: out, exits: exits, work: work };
    for s in p.symbols { if (s.flags & S_GLOBAL) != 0 && s.node >= 0 { cc_variable(p, f, s.node); } }
    cc_text(out, "}\n");
    if !p.library {
        if p.entry < 0 || !cc_emittable(p, p.entry) { diagnose_at(p, 0, 0, 0, "c: program has no checked concrete entry function"); }
        else {
            cc_text(out, "int main(int argc,char **argv){g_argc=argc;g_argv=argv;atexit(g_cleanup);g_initialize();");
            let result = cc_function_result(p, p.entry);
            if cc_kind(p, result) == TY_INT { cc_text(out, "return (int)"); }
            cc_id(out, "g_fn", p.entry); cc_text(out, "(NULL);");
            if cc_kind(p, result) != TY_INT { cc_text(out, "return 0;"); } cc_text(out, "}\n");
        }
    }
    if p.diagnostics.len > 0 { out.resize(begin); }
}
let cc_runtime_extra = """
static void g_debug_fail(const char *file,int line,const char *format,...) {
    fputs("goose runtime error: ",stderr); va_list args;va_start(args,format);
    vfprintf(stderr,format,args);va_end(args);fprintf(stderr," (%s:%d)\n",file,line);exit(1);
}
static void g_abort_value(GArray message,const char *file,int line) {
    fputs("goose runtime error: ",stderr);
    if(message.len)fwrite(message.data,1,(size_t)message.len,stderr);
    fprintf(stderr," (%s:%d)\n",file,line);exit(1);
}
static __int128 g_signed_min(int bits) { return -((__int128)1<<(bits-1)); }
static __int128 g_signed_max(int bits) { return ((__int128)1<<(bits-1))-1; }
static int64_t g_checked_binary(int64_t a,int64_t b,int bits,int op,const char *file,int line) {
    __int128 r=0;const char *text="?";
    if(op==21){r=(__int128)a+b;text="+";}
    else if(op==22){r=(__int128)a-b;text="-";}
    else if(op==23){r=(__int128)a*b;text="*";}
    else if(op==24){if(!b)g_debug_fail(file,line,"division by zero");if(a==INT64_MIN&&b==-1)g_debug_fail(file,line,"integer overflow in division");r=a/b;text="/";}
    if(r<g_signed_min(bits)||r>g_signed_max(bits))g_debug_fail(file,line,"integer overflow (debug): %" PRId64 " %s %" PRId64 " at i%d",a,text,b,bits);
    return (int64_t)r;
}
static int64_t g_checked_neg(int64_t a,int bits,const char *file,int line) {
    __int128 r=-(__int128)a;
    if(r<g_signed_min(bits)||r>g_signed_max(bits))g_debug_fail(file,line,"integer overflow (debug): -(%" PRId64 ") at i%d",a,bits);
    return (int64_t)r;
}
static uint64_t g_unsigned_max(int bits) { if(bits==64)return UINT64_MAX;return (UINT64_C(1)<<bits)-1; }
static uint64_t g_checked_cast_i(int64_t v,int bits,int uns,const char *file,int line) {
    int bad=0;if(uns){if(v<0||(uint64_t)v>g_unsigned_max(bits))bad=1;}
    else if((__int128)v<g_signed_min(bits)||(__int128)v>g_signed_max(bits))bad=1;
    if(bad){char kind='i';if(uns)kind='u';g_debug_fail(file,line,"as conversion out of range (debug): %" PRId64 " as %c%d",v,kind,bits);}
    return (uint64_t)v;
}
static uint64_t g_checked_cast_u(uint64_t v,int bits,int uns,const char *file,int line) {
    uint64_t hi=g_unsigned_max(bits);if(!uns)hi=(uint64_t)g_signed_max(bits);
    if(v>hi){char kind='i';if(uns)kind='u';g_debug_fail(file,line,"as conversion out of range (debug): %" PRIu64 " as %c%d",v,kind,bits);}
    return v;
}
static void g_cast_float_fail(const char *why,double v,int f32,int bits,int uns,const char *file,int line) {
    uint8_t text[64];int64_t count;char kind='i';if(uns)kind='u';
    if(f32)count=gs_fmt_f32(text,(float)v);else count=gs_fmt_f64(text,v);text[count]=0;
    g_debug_fail(file,line,"as conversion %s (debug): %s as %c%d",why,(char*)text,kind,bits);
}
static uint64_t g_checked_cast_f(double v,int f32,int bits,int uns,const char *file,int line) {
    if(uns&&bits==64){
        if(!(v>=0&&v<18446744073709551616.0))g_cast_float_fail("out of range",v,f32,bits,uns,file,line);
        uint64_t value=(uint64_t)v;
        if((double)value!=v)g_cast_float_fail("changes the value",v,f32,bits,uns,file,line);
        return value;
    }
    if(!(v>=-9223372036854775808.0&&v<9223372036854775808.0))g_cast_float_fail("out of range",v,f32,bits,uns,file,line);
    int64_t value=(int64_t)v;int bad=0;
    if(uns){if(value<0||(uint64_t)value>g_unsigned_max(bits))bad=1;}
    else if((__int128)value<g_signed_min(bits)||(__int128)value>g_signed_max(bits))bad=1;
    if(bad)g_cast_float_fail("out of range",v,f32,bits,uns,file,line);
    if((double)value!=v)g_cast_float_fail("changes the value",v,f32,bits,uns,file,line);
    return (uint64_t)value;
}
static unsigned char *g_nullable_address(GRef r) { if(!r)return NULL;return g_address(r); }
static double g_float_literal(uint64_t bits) { double v; memcpy(&v,&bits,sizeof v); return v; }
static int64_t g_clz(uint64_t x) { if(!x) return 64; return __builtin_clzll(x); }
static int64_t g_ctz(uint64_t x) { if(!x) return 64; return __builtin_ctzll(x); }
static int g_os_path_op(GSlice path,int op) { char *s=g_path(path); if(!s) return 0; if(op==0) return unlink(s)==0; if(op==1) return rmdir(s)==0; if(mkdir(s,0777)==0) return 1; return errno==EEXIST && g_os_kind(path)==2; }
static int g_os_rename(GSlice from,GSlice to) { char *a=g_path(from),*b=g_path(to); if(!a || !b) return 0; return rename(a,b)==0; }
static int g_os_resource(GRef out) { char path[4096]; ssize_t n=readlink("/proc/self/exe",path,sizeof path); if(n<=0 || n==(ssize_t)sizeof path) return 0; while(n>0 && path[n-1]!='/') n--; if(!n) return 0; GArray a; memcpy(&a,g_address(out),sizeof a); g_bytes(&a,path,n); memcpy(g_address(out),&a,sizeof a); return 1; }
static int g_trim_memory(void) { void *p=dlsym(RTLD_DEFAULT,"malloc_trim"); if(!p) return 0; return ((int (*)(size_t))p)(0); }
typedef struct { void *data; int64_t len; } GForeignSlice;
static GForeignSlice g_foreign_slice(GSlice s) { GForeignSlice r={g_address(s.base),s.len}; return r; }
static void *g_external(const char *library,const char *name) { void *handle=RTLD_DEFAULT; if(library) { handle=dlopen(library,RTLD_NOW|RTLD_LOCAL); if(!handle) g_panic(dlerror()); } void *p=dlsym(handle,name); if(!p) g_panic(dlerror()); return p; }
""";

fn cc_literal_array_args(p: Program&, out: u8[>..]&, type_id: i64, width: bool = true) {
    if cc_kind(p, type_id) != TY_SLICE { cc_array_args(p, out, type_id, width); return; }
    cc_text(out, "3,-1,0");
    if width { cc_text(out, ","); cc_number(out, p.types[p.types[type_id].element].size); }
}
fn cc_equal_fields(p: Program&, out: u8[>..]&, first: i64) {
    var field = first;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) == 0 {
            cc_text(out, "if(!"); cc_id(out, "g_equal_", n.type_id); cc_text(out, "(");
            cc_id(out, "g_load_", n.type_id); cc_text(out, "(g_offset(g_ref(&a),"); cc_number(out, n.integer); cc_text(out, ")),");
            cc_id(out, "g_load_", n.type_id); cc_text(out, "(g_offset(g_ref(&b),"); cc_number(out, n.integer); cc_text(out, "))))return 0;\n");
        }
        field = n.next;
    }
}
fn cc_emit_equal(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !cc_concrete(p, id) || t.kind == TY_VOID { return; }
    cc_text(out, "static int "); cc_id(out, "g_equal_", id); cc_text(out, "("); cc_type(out, id); cc_text(out, " a,"); cc_type(out, id); cc_text(out, " b){\n");
    if t.kind == TY_ARRAY || t.kind == TY_SLICE {
        cc_text(out, "GRef ar=g_ref(&a),br=g_ref(&b);int64_t n=g_len(ar,"); cc_array_args(p, out, id, false); cc_text(out, ");if(n!=g_len(br,"); cc_array_args(p, out, id, false); cc_text(out, "))return 0;\nfor(int64_t i=0;i<n;i++){if(!");
        cc_id(out, "g_equal_", t.element); cc_text(out, "("); cc_id(out, "g_load_", t.element); cc_text(out, "(g_element(ar,"); cc_array_args(p, out, id); cc_text(out, ",i,0)),");
        cc_id(out, "g_load_", t.element); cc_text(out, "(g_element(br,"); cc_array_args(p, out, id); cc_text(out, ",i,0))))return 0;}return 1;\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        cc_equal_fields(p, out, p.nodes[t.declaration].first); cc_text(out, "return 1;\n");
    } else if t.kind == TY_ENUM && t.declaration >= 0 {
        cc_text(out, "uint64_t tag=g_read_length(&a,"); cc_number(out, t.length_storage); cc_text(out, ");if(tag!=g_read_length(&b,"); cc_number(out, t.length_storage); cc_text(out, "))return 0;switch(tag){\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let payload = p.nodes[variant].type_id;
            cc_text(out, "case "); cc_number(out, p.nodes[variant].integer); cc_text(out, ":{\n"); cc_type(out, payload); cc_text(out, " av,bv;memcpy(&av,((unsigned char*)&a)+"); cc_number(out, t.length_storage); cc_text(out, ",sizeof av);memcpy(&bv,((unsigned char*)&b)+"); cc_number(out, t.length_storage); cc_text(out, ",sizeof bv);return "); cc_id(out, "g_equal_", payload); cc_text(out, "(av,bv);}\n");
            variant = p.nodes[variant].next;
        }
        cc_text(out, "default:g_panic(\"corrupt ADT tag\");}return 0;\n");
    } else if t.kind == TY_TUPLE {
        var field = t.first; var index = 0;
        while field >= 0 {
            cc_text(out, "if(!"); cc_id(out, "g_equal_", p.nodes[field].type_id); cc_text(out, "("); cc_id(out, "a.f", index); cc_text(out, ","); cc_id(out, "b.f", index); cc_text(out, "))return 0;\n");
            index++; field = p.nodes[field].next;
        }
        cc_text(out, "return 1;\n");
    } else if t.kind == TY_REF { cc_text(out, "return g_nullable_address(a)==g_nullable_address(b);\n"); }
    else { cc_text(out, "return a==b;\n"); }
    cc_text(out, "}\n");
}

fn cc_emit_nested(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !cc_concrete(p, id) || t.kind == TY_VOID { return; }
    cc_text(out, "static void "); cc_id(out, "g_nested_", id); cc_text(out, "(GArray *out,"); cc_type(out, id); cc_text(out, " v){\n");
    if (t.kind == TY_ARRAY || t.kind == TY_SLICE) && cc_kind(p, t.element) == TY_INT && p.types[t.element].count == 8 && (p.types[t.element].flags & TF_UNSIGNED) != 0 {
        cc_text(out, "GRef r=g_ref(&v);int64_t n=g_len(r,"); cc_array_args(p, out, id, false); cc_text(out, ");if(n<0 || (uint64_t)n>(SIZE_MAX-2)/2)g_panic(\"text size overflow\");unsigned char *b=g_alloc((size_t)n*2+2);int64_t written=gs_fmt_quoted(b,g_address(g_element(r,"); cc_array_args(p, out, id); cc_text(out, ",0,1)),n);g_print_bytes(out,b,written);\n");
    } else if t.kind == TY_REF && cc_kind(p, t.element) == TY_VOID {
        cc_text(out, "g_print_text(out,\"null\");\n");
    } else if t.kind == TY_REF {
        cc_text(out, "if(!v)g_print_text(out,\"null\");else "); cc_id(out, "g_nested_", t.element); cc_text(out, "(out,"); cc_id(out, "g_load_", t.element); cc_text(out, "(v));\n");
    } else { cc_id(out, "g_print_", id); cc_text(out, "(out,v);\n"); }
    cc_text(out, "}\n");
}

fn cc_zero_initializer(p: Program&, out: u8[>..]&, type_id: i64) {
    if cc_aggregate(p, type_id) && p.types[type_id].size == 0 { cc_text(out, "{}"); }
    else { cc_text(out, "{0}"); }
}

recursive fn cc_needs_clone(p: Program&, type_id: i64, depth: i64) -> bool {
    if type_id < 0 { return false; }
    if depth > 64 { return true; }
    let t = p.types[type_id];
    if t.kind == TY_ARRAY {
        if cc_owner(p, type_id) { return true; }
        return cc_needs_clone(p, t.element, depth + 1);
    }
    if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 && cc_needs_clone(p, p.nodes[field].type_id, depth + 1) { return true; }
            field = p.nodes[field].next;
        }
    }
    if t.kind == TY_ENUM && t.declaration >= 0 {
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            if cc_needs_clone(p, p.nodes[variant].type_id, depth + 1) { return true; }
            variant = p.nodes[variant].next;
        }
    }
    if t.kind == TY_TUPLE {
        var part = t.first;
        while part >= 0 {
            if cc_needs_clone(p, p.nodes[part].type_id, depth + 1) { return true; }
            part = p.nodes[part].next;
        }
    }
    return false;
}

fn cc_conversion_fail(p: Program&, node: i64, from: i64, to: i64) {
    var message: u8[>..] = [];
    message.format("c: unsupported checked value conversion ", from, " (kind ", cc_kind(p, from), ") to ", to, " (kind ", cc_kind(p, to), ")");
    cc_fail(p, node, message);
}

fn cc_location(p: Program&, out: u8[>..]&, node: i64) {
    let token = p.nodes[node].token;
    if token < 0 || token >= p.tokens.len { cc_text(out, "\"<generated>\",1"); return; }
    let t = p.tokens[token];
    if t.source < 0 || t.source >= p.sources.len { cc_text(out, "\"<generated>\""); }
    else {
        let source = p.sources[t.source]; cc_bytes(out, p.text[source.path_start..source.path_start + source.path_len]);
    }
    cc_text(out, ","); cc_number(out, t.line);
}
recursive fn cc_cast(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; let target = p.types[n.type_id];
    var source = p.nodes[n.left].type_id;
    while cc_kind(p, source) == TY_REF { source = p.types[source].element; }
    var value = -1;
    if target.kind == TY_INT && target.index_type >= 0 && (n.flags & F_BOUNDS_PROVEN) == 0 {
        let symbol = target.pool;
        if symbol < 0 || cc_kind(p, source) != TY_INT { cc_fail(p, node, "c: index cast requires an integer and array owner"); return -1; }
        value = cc_to(p, f, n.left, source);
        var owner = cc_symbol_ref(p, f, symbol, node); var owner_type = p.symbols[symbol].type_id;
        while cc_kind(p, owner_type) == TY_REF { owner = cc_load(p, f, owner, owner_type); owner_type = p.types[owner_type].element; }
        let length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", owner);
        cc_text(f.out, ","); cc_array_args(p, f.out, owner_type, false); cc_text(f.out, ");\nif((uint64_t)"); cc_id(f.out, "g_v", value);
        if (target.flags & F_BOUND_TYPE) != 0 { cc_text(f.out, ">"); } else { cc_text(f.out, ">="); }
        cc_text(f.out, "(uint64_t)"); cc_id(f.out, "g_v", length); cc_text(f.out, ")g_index_fail("); cc_id(f.out, "g_v", value);
        cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
    }
    if !p.debug || (n.flags & F_UNSIGNED) != 0 || target.kind != TY_INT {
        if value >= 0 { return cc_convert(p, f, value, source, n.type_id, node); }
        return cc_to(p, f, n.left, n.type_id);
    }
    if cc_kind(p, source) != TY_INT && cc_kind(p, source) != TY_FLOAT { return cc_to(p, f, n.left, n.type_id); }
    if value < 0 { value = cc_to(p, f, n.left, source); }
    let result = cc_temp(p, f, n.type_id);
    cc_set(f, result); cc_text(f.out, "("); cc_type(f.out, n.type_id); cc_text(f.out, ")g_checked_cast_");
    if p.types[source].kind == TY_FLOAT { cc_text(f.out, "f("); }
    else if (p.types[source].flags & TF_UNSIGNED) != 0 { cc_text(f.out, "u("); }
    else { cc_text(f.out, "i("); }
    cc_id(f.out, "g_v", value); cc_text(f.out, ",");
    if p.types[source].kind == TY_FLOAT {
        var source_f32 = 0; if p.types[source].count == 32 { source_f32 = 1; }
        cc_number(f.out, source_f32); cc_text(f.out, ",");
    }
    cc_number(f.out, target.count); cc_text(f.out, ",");
    var uns = 0; if (target.flags & TF_UNSIGNED) != 0 { uns = 1; }
    cc_number(f.out, uns); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return result;
}

fn cc_has_capture(p: Program&, function: i64, symbol: i64) -> bool {
    var capture = p.nodes[function].captures;
    while capture >= 0 {
        if p.nodes[capture].symbol == symbol { return true; }
        capture = p.nodes[capture].next;
    }
    return false;
}
fn cc_capture_call(p: Program&, function: i64, callee: i64) -> bool {
    if callee < 0 || callee >= p.nodes.len { return false; }
    var changed = false; var capture = p.nodes[callee].captures;
    while capture >= 0 {
        let symbol = p.nodes[capture].symbol;
        if symbol >= 0 && p.symbols[symbol].owner >= 0 && p.symbols[symbol].owner != function &&
           (p.symbols[symbol].flags & (S_GLOBAL | S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 && !cc_has_capture(p, function, symbol) {
            let id = new_node(p, N_BINDING, p.symbols[symbol].name_token);
            p.nodes[id].symbol = symbol; p.nodes[id].type_id = p.symbols[symbol].type_id;
            p.nodes[id].flags = F_CHECKED;
            let first = p.nodes[function].captures;
            if first < 0 { p.nodes[function].captures = id; }
            else {
                var last = first;
                while p.nodes[last].next >= 0 { last = p.nodes[last].next; }
                p.nodes[last].next = id;
            }
            p.nodes[function].flags |= F_CAPTURE; changed = true;
        }
        capture = p.nodes[capture].next;
    }
    return changed;
}
recursive fn cc_capture_tree(p: Program&, function: i64, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_FUNCTION { return false; }
    if n.kind == N_FUNCTION_VALUE { return cc_capture_call(p, function, node); }
    if n.kind == N_RETURN && n.symbol >= 0 && n.symbol < p.symbols.len {
        let target = p.symbols[n.symbol].node;
        if target >= 0 && target != function { p.nodes[target].flags |= F_NONLOCAL; }
    }
    var changed = false;
    if (n.kind == N_CALL || n.kind == N_NAME) && n.symbol >= 0 &&
       (p.symbols[n.symbol].flags & S_FUNCTION) != 0 && (p.symbols[n.symbol].flags & S_BUILTIN) == 0 {
        changed = cc_capture_call(p, function, p.symbols[n.symbol].node);
    }
    if n.kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
        var arm = n.third;
        while arm >= 0 {
            let symbol = p.nodes[arm].symbol;
            if symbol >= 0 && cc_capture_call(p, function, p.symbols[symbol].node) { changed = true; }
            arm = p.nodes[arm].next;
        }
    }
    // A match pattern names variant nodes, not symbols or executable callees.
    if n.kind != N_ARM && cc_capture_tree(p, function, n.left) { changed = true; }
    if cc_capture_tree(p, function, n.right) { changed = true; }
    if cc_capture_tree(p, function, n.third) { changed = true; }
    var child = n.first;
    while child >= 0 {
        if cc_capture_tree(p, function, child) { changed = true; }
        child = p.nodes[child].next;
    }
    return changed;
}
fn cc_collect_captures(p: Program&) {
    var changed = true;
    while changed {
        changed = false;
        let count = p.nodes.len;
        for function in 0..count {
            if cc_emittable(p, function) && p.nodes[function].right >= 0 &&
               cc_capture_tree(p, function, p.nodes[function].right) { changed = true; }
        }
    }
}

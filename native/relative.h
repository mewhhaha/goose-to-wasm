/* Canonical packed cells hold offsets; expression values are addresses. */
/* Standalone scalar slots keep their encoded extent; this control is never
   copied into canonical aggregate bytes. Natural values remain GRef. */
typedef struct { uint8_t bytes[10]; uint8_t extent; } GVarRelative;

static const uint8_t *g_relative_var_skip(const uint8_t *cell,const uint8_t *end) {
    uint64_t bits=0;int64_t size=gs_uleb_check(cell,end,&bits);
    if(!size)g_panic("invalid relative reference encoding");
    return cell+size;
}
static GRef g_relative_var_load(GRef cell,const uint8_t *end,int optional,GRef pool_origin,const uint8_t **next) {
    uint64_t bits=0;int64_t size=gs_uleb_check(g_address(cell),end,&bits);
    if(!size)g_panic("invalid relative reference encoding");
    if(next)*next=g_address(cell)+size;
    if(optional && !bits)return 0;
    GRef origin=pool_origin;if(!origin)origin=cell;
    if(pool_origin) {
        if(bits>UINTPTR_MAX-origin)g_panic("relative reference address overflow");
        return origin+(uintptr_t)bits;
    }
    uint64_t offset=(bits>>1)^(UINT64_C(0)-(bits&1));
    if(offset>>63) {
        uint64_t magnitude=UINT64_C(0)-offset;
        if(magnitude>origin)g_panic("relative reference address overflow");
        return origin-(uintptr_t)magnitude;
    }
    if(offset>UINTPTR_MAX-origin)g_panic("relative reference address overflow");
    return origin+(uintptr_t)offset;
}

static uint64_t g_relative_offset(GRef cell,GRef value,int optional,GRef pool_origin,const char *file,int line) {
    if(!value && optional)return 0;
    GRef origin=pool_origin;if(!origin)origin=cell;
    uint64_t bits=0;
    if(pool_origin) {
        if(value<origin)gs_abort(GS_E_RELOFF,file,line);
        return (uint64_t)(value-origin);
    }
    if(value>=origin) {
        bits=(uint64_t)(value-origin);
        if(bits>INT64_MAX)gs_abort(GS_E_RELOFF,file,line);
    } else {
        uint64_t magnitude=(uint64_t)(origin-value);
        if(magnitude>(UINT64_C(1)<<63))gs_abort(GS_E_RELOFF,file,line);
        bits=UINT64_C(0)-magnitude;
    }
    if(optional && !bits)gs_abort(GS_E_RELNULL,file,line);
    return bits;
}
static uint8_t *g_relative_var_store(GRef cell,uint8_t *end,GRef value,int optional,GRef pool_origin,const char *file,int line) {
    uint64_t bits=g_relative_offset(cell,value,optional,pool_origin,file,line);
    if(!pool_origin)bits=(bits<<1)^(UINT64_C(0)-(bits>>63));
    uint8_t encoded[10];int64_t size=gs_uleb_write(encoded,bits);
    if(end<g_address(cell) || size>end-g_address(cell))g_panic("relative reference cell capacity exceeded");
    memcpy(g_address(cell),encoded,(size_t)size);
    return g_address(cell)+size;
}

static GRef g_relative_load(GRef cell,int width,int optional,GRef pool_origin) {
    if(!width) {
        GVarRelative *value=(GVarRelative*)g_address(cell);
        if(!value->extent || value->extent>sizeof value->bytes)g_panic("invalid relative reference extent");
        const uint8_t *end=value->bytes+value->extent,*next=NULL;
        GRef result=g_relative_var_load(cell,end,optional,pool_origin,&next);
        if(next!=end)g_panic("invalid relative reference extent");
        return result;
    }
    uint64_t bits=0;memcpy(&bits,g_address(cell),(size_t)width);
    if(optional && !bits)return 0;
    GRef origin=pool_origin;if(!origin)origin=cell;
    if(!pool_origin && width<8 && (bits&(UINT64_C(1)<<(width*8-1))))bits|=UINT64_MAX<<(width*8);
    return origin+(uintptr_t)bits;
}
static void g_relative_store(GRef cell,GRef value,int width,int optional,GRef pool_origin,const char *file,int line) {
    if(!width) {
        GVarRelative *target=(GVarRelative*)g_address(cell);
        uint8_t *end=g_relative_var_store(cell,target->bytes+sizeof target->bytes,value,optional,pool_origin,file,line);
        target->extent=(uint8_t)(end-target->bytes);
        return;
    }
    if(!value && optional){memset(g_address(cell),0,(size_t)width);return;}
    GRef origin=pool_origin;if(!origin)origin=cell;
    uint64_t bits=0;
    if(pool_origin) {
        if(value<origin)gs_abort(GS_E_RELOFF,file,line);
        bits=(uint64_t)(value-origin);
        if(width<8 && bits>=(UINT64_C(1)<<(width*8)))gs_abort(GS_E_RELOFF,file,line);
    } else {
        if(value>=origin) {
            bits=(uint64_t)(value-origin);
            if(bits>INT64_MAX)gs_abort(GS_E_RELOFF,file,line);
        } else {
            uint64_t magnitude=(uint64_t)(origin-value);
            if(magnitude>(UINT64_C(1)<<63))gs_abort(GS_E_RELOFF,file,line);
            bits=UINT64_C(0)-magnitude;
        }
        if(optional && !bits)gs_abort(GS_E_RELNULL,file,line);
        if(width<8) {
            int64_t offset=(int64_t)bits;int64_t limit=INT64_C(1)<<(width*8-1);
            if(offset < -limit || offset>=limit)gs_abort(GS_E_RELOFF,file,line);
        }
    }
    memcpy(g_address(cell),&bits,(size_t)width);
}

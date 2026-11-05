/* Canonical packed cells hold offsets; expression values are addresses. */
static GRef g_relative_load(GRef cell,int width,int optional,GRef pool_origin) {
    uint64_t bits=0;memcpy(&bits,g_address(cell),(size_t)width);
    if(optional && !bits)return 0;
    GRef origin=pool_origin;if(!origin)origin=cell;
    if(!pool_origin && width<8 && (bits&(UINT64_C(1)<<(width*8-1))))bits|=UINT64_MAX<<(width*8);
    return origin+(uintptr_t)bits;
}
static void g_relative_store(GRef cell,GRef value,int width,int optional,GRef pool_origin,const char *file,int line) {
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

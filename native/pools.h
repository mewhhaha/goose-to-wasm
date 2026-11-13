/* Reusable array companions share the owner's planned lifetime. */
static GRegion *g_pool_region(GRef header,int mode) {
    GArray value;memcpy(&value,g_address(header),sizeof value);
    if(!value.region || !value.region->freelist || value.region->free_mode!=mode)g_panic("pool has no receiving freelist");
    return value.region;
}
static void g_pool_init(GRef header,int64_t slot,int mode) {
    GArray value;memcpy(&value,g_address(header),sizeof value);
    if(!value.region)g_panic("pool has no receiving region");
    // Slice requests are sized against the owner's reservation.
    if(value.data==&g_empty_byte)g_array_place(header);
    GRegion *free=g_region(slot);free->entry=free->stack.top;
    value.region->freelist=free;value.region->free_count=0;value.region->free_mode=mode;
}
static void g_pool_require(GRegion *region,size_t bytes) {
    size_t offset=(size_t)(region->stack.top-region->base);
    if(bytes>region->usable || offset>region->usable-bytes)g_panic("pool freelist region exhausted");
}
static void g_pool_tree_require(GRegion *owner) {
    g_pool_require(owner->freelist,(G_SPAN_DEPTH+2)*GS_SPAN_NODE);
}
static int64_t g_pool_take(GRef header,int64_t width) {
    GRegion *owner=g_pool_region(header,1);GArray value;memcpy(&value,g_address(header),sizeof value);
    int64_t index=value.len;
    if(owner->free_count) {
        owner->free_count--;owner->freelist->stack.top-=8;memcpy(&index,owner->freelist->stack.top,8);
    } else {
        if(index==INT64_MAX)g_panic("array length overflow");g_reserve(header,3,-1,0,width,index+1);
    }
    return index;
}
static void g_pool_commit(GRef header,int64_t index) {
    GArray value;memcpy(&value,g_address(header),sizeof value);
    if(index==value.len)g_set_len(header,3,-1,0,index+1);
}
static void g_pool_free(GRef header,int64_t index,const char *file,int line) {
    GRegion *owner=g_pool_region(header,1);GArray value;memcpy(&value,g_address(header),sizeof value);
    if(index<0 || index>=value.len)g_index_fail(index,value.len,file,line);
    GRegion *free=owner->freelist;g_pool_require(free,8);memcpy(free->stack.top,&index,8);free->stack.top+=8;owner->free_count++;
}
static int64_t g_pool_slice_index(GRef header,GSlice slice,int64_t width,const char *file,int line) {
    if(!slice.len)return 0;
    GArray value;memcpy(&value,g_address(header),sizeof value);
    uint64_t offset=(uint64_t)(slice.base-(uintptr_t)value.data);
    if(slice.len<0 || offset%(uint64_t)width || offset/(uint64_t)width>=(uint64_t)value.len ||
       (uint64_t)slice.len>(uint64_t)value.len-offset/(uint64_t)width)gs_abort(GS_E_POOLSLICE,file,line);
    return (int64_t)(offset/(uint64_t)width);
}
static void g_pool_slice_free(GRef header,GSlice slice,int64_t width,const char *file,int line) {
    GRegion *owner=g_pool_region(header,2);int64_t index=g_pool_slice_index(header,slice,width,file,line);
    if(!slice.len)return;g_pool_tree_require(owner);
    gs_spans_free(owner->freelist->entry,&owner->free_count,&owner->freelist->stack.top,index,slice.len);
}
static GSlice g_pool_slice_resize(GRef header,GSlice old,int64_t count,int64_t width,const char *file,int line) {
    GRegion *owner=g_pool_region(header,2);GRegion *free=owner->freelist;
    GArray value;memcpy(&value,g_address(header),sizeof value);
    if(count<0 || width<=0 || (uint64_t)count>value.region->usable/(uint64_t)width)gs_abort(GS_E_SLICELEN,file,line);
    int64_t index=g_pool_slice_index(header,old,width,file,line);g_pool_tree_require(owner);
    if(count<=old.len) {
        gs_spans_free(free->entry,&owner->free_count,&free->stack.top,index+count,old.len-count);
    } else {
        if(!old.len)index=gs_spans_alloc(free->entry,&owner->free_count,&free->stack.top,value.len,count);
        else if(index+old.len!=value.len)index=gs_spans_regrow(free->entry,&owner->free_count,&free->stack.top,value.len,index,old.len,count);
        if(index>INT64_MAX-count)g_panic("pool slice length overflow");
        int64_t end=index+count;g_reserve(header,3,-1,0,width,end);
        if(old.len)memmove(value.data+(size_t)index*(size_t)width,g_address(old.base),(size_t)old.len*(size_t)width);
        if(end>value.len)g_set_len(header,3,-1,0,end);
    }
    return (GSlice){g_moving(header,index*width),count};
}
static int64_t g_pool_image_size(GRef header) {
    GArray value;memcpy(&value,g_address(header),sizeof value);GRegion *owner=value.region;
    int64_t width=8;if(owner->free_mode==2)width=GS_SPAN_NODE;
    if(owner->free_count>(INT64_MAX-8)/width)g_panic("pool image size overflow");return 8+owner->free_count*width;
}
static uint8_t *g_pool_image_write(uint8_t *image,GRef header) {
    GArray value;memcpy(&value,g_address(header),sizeof value);GRegion *owner=value.region;
    int64_t bytes=g_pool_image_size(header)-8;memcpy(image,&owner->free_count,8);
    if(bytes)memcpy(image+8,owner->freelist->entry,(size_t)bytes);return image+8+bytes;
}
static const uint8_t *g_pool_image_read(GRef header,const uint8_t *image,int64_t slot,int mode) {
    g_pool_init(header,slot,mode);GRegion *owner=g_pool_region(header,mode);int64_t count;memcpy(&count,image,8);
    int64_t width=8;if(mode==2)width=GS_SPAN_NODE;
    if(count<0 || count>INT64_MAX/width)g_panic("invalid pool image length");int64_t bytes=count*width;
    g_pool_require(owner->freelist,(size_t)bytes);
    if(bytes)memcpy(owner->freelist->entry,image+8,(size_t)bytes);
    owner->free_count=count;owner->freelist->stack.top=owner->freelist->entry+bytes;return image+8+bytes;
}

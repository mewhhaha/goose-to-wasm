/* Canonical value images and private resizable transfer envelopes. */
typedef struct __attribute__((packed)) { uint8_t *base,*end;GRegion *region; } GImage;
static GImage g_image(int64_t slot) {
    GArray owner=g_mapped_array(slot);return (GImage){owner.data,owner.data,owner.region};
}
static uint8_t *g_image_space(GRegion *region,int64_t bytes) {
    if(!region || !region->base || bytes<0)g_panic("invalid image reservation");
    uintptr_t base=(uintptr_t)region->base,top=(uintptr_t)region->stack.top;
    if(top<base || top-base>region->usable || (uint64_t)bytes>region->usable-(top-base))g_panic("image region exhausted");
    return region->stack.top;
}
static void g_image_advance(GRegion *region,uint8_t *end) {
    g_image_space(region,0);
    uintptr_t base=(uintptr_t)region->base,top=(uintptr_t)region->stack.top,next=(uintptr_t)end;
    if(next<top || next-base>region->usable)g_panic("invalid image cursor");
    region->stack.top=end;
    uint64_t used=(uint64_t)(next-base);if(used>region->high_water)region->high_water=used;
}
static int64_t g_image_span(GImage image) {
    uintptr_t base=(uintptr_t)image.base,end=(uintptr_t)image.end;
    if(end<base || end-base>INT64_MAX)g_panic("invalid image span");
    return (int64_t)(end-base);
}
static void g_image_finish(GRef destination,uint8_t *end) {
    GImage image;memcpy(&image,g_address(destination),sizeof image);
    if((uintptr_t)end<(uintptr_t)image.base)g_panic("invalid image end");
    g_image_advance(image.region,end);image.end=end;
    memcpy(g_address(destination),&image,sizeof image);g_header_changed(destination);
}
static void g_image_zero(GRef destination,int64_t bytes) {
    GImage image;memcpy(&image,g_address(destination),sizeof image);
    image.region->stack.top=image.base;
    uint8_t *data=g_image_space(image.region,bytes);memset(data,0,(size_t)bytes);
    g_image_finish(destination,data+bytes);
}
static void g_image_commit(GRef destination,uint8_t *end,int64_t count) {
    GArray owner;memcpy(&owner,g_address(destination),sizeof owner);
    if(count<0 || (uintptr_t)end<(uintptr_t)owner.data)g_panic("invalid image count");
    g_image_advance(owner.region,end);owner.len=count;
    memcpy(g_address(destination),&owner,sizeof owner);g_header_changed(destination);
}
static void g_image_copy_into(GRef destination,GImage source) {
    GImage image;memcpy(&image,g_address(destination),sizeof image);
    int64_t bytes=g_image_span(source);
    if(!image.region || !image.region->base)g_panic("image has no receiving region");
    uintptr_t base=(uintptr_t)image.region->base,start=(uintptr_t)image.base;
    if(start<base || start-base>image.region->usable || (uint64_t)bytes>image.region->usable-(start-base))g_panic("image region exhausted");
    if(image.base==source.base) {
        image.end=source.end;memcpy(g_address(destination),&image,sizeof image);g_header_changed(destination);return;
    }
    if(bytes)memmove(image.base,source.base,(size_t)bytes);
    image.region->stack.top=image.base;g_image_finish(destination,image.base+bytes);
}
static int64_t g_image_add(int64_t total,int64_t bytes) {
    if(total<0 || bytes<0 || bytes>INT64_MAX-total)g_panic("image size overflow");
    return total+bytes;
}
static int64_t g_image_product(int64_t count,int64_t width) {
    if(count<0 || width<0 || (width && count>INT64_MAX/width))g_panic("image size overflow");
    return count*width;
}
static int64_t g_image_uleb_width(uint64_t value) {
    int64_t width=1;while(value>=128){value>>=7;width++;}return width;
}
static const uint8_t *g_image_count_read(const uint8_t *image,int width,int64_t *count) {
    uint64_t value=0;
    if(!width){value=(uint64_t)gs_uleb_read(image);image+=gs_uleb_size(image);}
    else {memcpy(&value,image,(size_t)width);image+=width;}
    if(value>INT64_MAX)g_panic("image count exceeds native range");*count=(int64_t)value;return image;
}
static uint8_t *g_image_count_write(uint8_t *image,int width,int64_t count) {
    if(count<0)g_panic("negative image count");
    if(!width)return image+gs_uleb_write(image,(uint64_t)count);
    if(width<8 && (uint64_t)count>=(UINT64_C(1)<<(width*8)))g_panic("array length exceeds storage range");
    memcpy(image,&count,(size_t)width);return image+width;
}
static void g_image_array_begin(GRef destination,int kind,int prefix,int64_t count,int64_t capacity,int64_t width) {
    GImage image;memcpy(&image,g_address(destination),sizeof image);
    if(!image.region)g_panic("image has no receiving region");
    image.region->stack.top=image.base;uint8_t *cursor;
    if(kind==2) {
        if(count<0 || capacity<count || (uint64_t)capacity>UINT32_MAX)g_panic("limited array capacity exceeded");
        cursor=g_image_space(image.region,g_image_add(8,g_image_product(capacity,width)));
        cursor=g_image_count_write(cursor,4,capacity);cursor=g_image_count_write(cursor,4,count);
    } else {
        int64_t bytes=prefix;if(!bytes)bytes=g_image_uleb_width((uint64_t)count);
        cursor=g_image_count_write(g_image_space(image.region,bytes),prefix,count);
    }
    g_image_advance(image.region,cursor);
}
static void g_image_array_finish(GRef destination,int kind,int64_t capacity,int64_t width) {
    GImage image;memcpy(&image,g_address(destination),sizeof image);uint8_t *end=image.region->stack.top;
    if(kind==2) {
        end=image.base+g_image_add(8,g_image_product(capacity,width));
        if((uintptr_t)image.region->stack.top>(uintptr_t)end)g_panic("limited array capacity exceeded");
        memset(image.region->stack.top,0,(size_t)(end-image.region->stack.top));
    }
    g_image_finish(destination,end);
}
static void g_image_limited_assign(GRef destination,GImage source,int64_t width) {
    uint8_t *target=g_address(destination);int64_t count=(int64_t)g_read_length(source.base+4,4);
    if(count>(int64_t)g_read_length(target,4))g_panic("limited array capacity exceeded");
    int64_t bytes=g_image_product(count,width);g_write_length(target+4,4,(uint64_t)count);
    if(bytes)memmove(target+8,source.base+8,(size_t)bytes);
}
static const uint8_t *g_image_copy(const uint8_t *image,int64_t bytes,int64_t slot) {
    GArray saved=g_array(slot);g_reserve(g_ref(&saved),3,-1,0,1,bytes);
    if(bytes)memcpy(saved.data,image,(size_t)bytes);g_set_len(g_ref(&saved),3,-1,0,bytes);return saved.data;
}
static uint8_t *g_image_data(GRef source,int kind,int64_t fixed,int prefix) {
    if(kind==5){GSlice value;memcpy(&value,g_address(source),sizeof value);return g_address(value.base);}
    if(kind==0)return g_address(source);
    if(kind==1){if(!prefix)prefix=gs_uleb_size(g_address(source));return g_address(source)+prefix;}
    if(kind==2 && fixed<0)return g_address(source)+8;
    if(kind==2 && fixed>=0)return g_address(source)+prefix;
    GArray value;memcpy(&value,g_address(source),sizeof value);return value.data;
}
static const uint8_t *g_image_count_check(const uint8_t *image,const uint8_t *end,int width,int64_t *count) {
    uint64_t value=0;
    if(!width) {
        int64_t bytes=gs_uleb_check(image,end,&value);if(!bytes)return NULL;image+=bytes;
    } else {
        if(end-image<width)return NULL;memcpy(&value,image,(size_t)width);image+=width;
    }
    if(value>INT64_MAX)return NULL;*count=(int64_t)value;return image;
}
static const uint8_t *g_image_slice_data(GSlice value) {
    if(!value.base && !value.len)return &g_empty_byte;return g_address(value.base);
}

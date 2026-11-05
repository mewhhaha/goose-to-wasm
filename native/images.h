/* Canonical value images and private resizable transfer envelopes. */
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
static const uint8_t *g_image_copy(const uint8_t *image,int64_t bytes,int64_t slot) {
    GArray saved=g_array(slot);g_reserve(g_ref(&saved),3,-1,0,1,bytes);
    if(bytes)memcpy(saved.data,image,(size_t)bytes);g_set_len(g_ref(&saved),3,-1,0,bytes);return saved.data;
}
static uint8_t *g_image_data(GRef source,int kind,int64_t fixed,int prefix) {
    if(kind==5){GSlice value;memcpy(&value,g_address(source),sizeof value);return g_address(value.base);}
    if(kind==0)return g_address(source);
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

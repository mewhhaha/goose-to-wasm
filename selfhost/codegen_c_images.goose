import model;
import codegen_c_storage;

// Frame access is typed; images contain no native owner headers.
fn ci_prefix(p: Program&, id: i64) -> i64 {
    let t = p.types[id];
    if t.kind == TY_SLICE || t.array_kind == A_GROW || t.array_kind == A_GROWSHRINK { return 8; }
    if t.array_kind == A_VAR { return t.length_storage; }
    if t.array_kind == A_LIMITED && t.count >= 0 { if t.length_storage > 0 { return t.length_storage; } return 1; }
    return 0;
}
recursive fn ci_direct(p: Program&, id: i64) -> bool {
    let t = p.types[id];
    if t.storage != 0 || cc_region_width(p, id) > 0 { return false; }
    if cc_relative_cell(p, id) { return true; }
    if t.kind == TY_VOID || t.kind == TY_INT || t.kind == TY_FLOAT || t.kind == TY_BOOL { return true; }
    if t.kind == TY_ARRAY { return t.array_kind == A_FIXED && ci_direct(p, t.element); }
    if (t.kind == TY_STRUCT && t.declaration >= 0) || t.kind == TY_TUPLE {
        var field = t.first; if t.kind == TY_STRUCT { field = p.nodes[t.declaration].first; }
        while field >= 0 {
            let n = p.nodes[field]; if (n.flags & F_PAD) == 0 && !ci_direct(p, n.type_id) { return false; }
            field = n.next;
        }
        return true;
    }
    if t.kind == TY_ENUM && t.declaration >= 0 && (t.flags & F_VARIABLE_MODE) == 0 {
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 { if !ci_direct(p, p.nodes[variant].type_id) { return false; } variant = p.nodes[variant].next; }
        return true;
    }
    return false;
}
fn ci_array_args(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; var kind = t.array_kind; if t.kind == TY_SLICE { kind = A_SLICE; }
    out.format(kind, ",", t.count, ",");
    var prefix = 0; if t.array_kind == A_LIMITED && t.count >= 0 { prefix = ci_prefix(p, id); }
    out.format(prefix);
}
fn ci_element(p: Program&, out: u8[>..]&, id: i64, base: const u8[:]) {
    out.format("g_ref(g_image_data(", base, ","); ci_array_args(p, out, id);
    out.format(")+i*", cc_frame_size(p, p.types[id].element), ")");
}
fn ci_fields(p: Program&, out: u8[>..]&, id: i64, operation: i64) {
    let t = p.types[id]; var field = t.first; if t.kind == TY_STRUCT { field = p.nodes[t.declaration].first; }
    var ordinal = 0;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) != 0 {
            if operation == 0 { out.format("size=g_image_add(size,", n.aux, ");\n"); }
            else if operation == 1 { out.format("image+=", n.aux, ";\n"); }
            else if operation == 2 { out.format("memcpy(image,g_address(g_offset(source,", cc_field_offset(p, id, field), ")),", n.aux, ");image+=", n.aux, ";\n"); }
            else { out.format("memcpy(g_address(g_offset(dest,", cc_field_offset(p, id, field), ")),image,", n.aux, ");image+=", n.aux, ";\n"); }
        } else {
            if operation == 0 { out.format("size=g_image_add(size,g_image_size_", n.type_id, "("); }
            else if operation == 1 {
                if cc_image_type(p, id) { out.format("image=g_physical_skip_", n.type_id, "(image);\n"); }
                else { out.format("image=g_image_skip_", n.type_id, "(image);\n"); }
            }
            else if operation == 2 { out.format("image=g_image_write_", n.type_id, "(image,"); }
            else { out.format("image=g_image_unpack_", n.type_id, "("); }
            if operation != 1 {
                var base: const u8[:] = "source"; if operation == 3 { base = "dest"; }
                if t.kind == TY_TUPLE { out.format("g_offset(", base, ",offsetof(g_t", id, ",f", ordinal, "))"); }
                else { out.format("g_offset(", base, ",", cc_field_offset(p, id, field), ")"); }
                if operation == 0 { out.append("));\n"); }
                else if operation == 2 { out.append(");\n"); }
                else { out.append(",image);\n"); }
            }
            ordinal++;
        }
        field = n.next;
    }
}
fn ci_array_header(p: Program&, out: u8[>..]&, id: i64, operation: i64) {
    let t = p.types[id]; let prefix = ci_prefix(p, id);
    if operation == 0 || operation == 2 {
        out.append("int64_t count=g_len(source,"); ci_array_args(p, out, id); out.append(");int64_t slots=count;\n");
        if t.kind == TY_ARRAY && t.array_kind == A_LIMITED {
            if t.count >= 0 { out.format("slots=", t.count, ";\n"); }
            else { out.append("slots=g_cap(source,2,-1);\n"); }
        }
        if operation == 0 {
            if t.kind == TY_ARRAY && t.array_kind == A_FIXED { out.append("int64_t size=0;\n"); }
            else if t.kind == TY_ARRAY && t.array_kind == A_LIMITED && t.count < 0 { out.append("int64_t size=8;\n"); }
            else if prefix == 0 { out.append("int64_t size=g_image_uleb_width((uint64_t)count);\n"); }
            else { out.format("int64_t size=", prefix, ";\n"); }
        } else {
            if t.kind == TY_ARRAY && t.array_kind == A_FIXED { return; }
            if t.kind == TY_ARRAY && t.array_kind == A_LIMITED && t.count < 0 { out.append("image=g_image_count_write(image,4,slots);image=g_image_count_write(image,4,count);\n"); }
            else { out.format("image=g_image_count_write(image,", prefix, ",count);\n"); }
        }
    } else {
        if t.kind == TY_ARRAY && t.array_kind == A_FIXED { out.format("int64_t count=", t.count, ",slots=count;\n"); }
        else {
            out.append("int64_t count,slots;\n");
            if t.kind == TY_ARRAY && t.array_kind == A_LIMITED && t.count < 0 {
                out.append("image=g_image_count_read(image,4,&slots);image=g_image_count_read(image,4,&count);if(count>slots)g_panic(\"invalid limited image\");\n");
            } else {
                out.format("image=g_image_count_read(image,", prefix, ",&count);\n");
                if t.kind == TY_ARRAY && t.array_kind == A_LIMITED { out.format("slots=", t.count, ";if(count>slots)g_panic(\"invalid limited image\");\n"); }
                else { out.append("slots=count;\n"); }
            }
        }
    }
}
fn ci_enum(p: Program&, out: u8[>..]&, id: i64, operation: i64) {
    let t = p.types[id]; let fixed = (t.flags & F_VARIABLE_MODE) == 0;
    if operation == 0 { out.format("int64_t size=", t.length_storage, ";switch(g_read_length(g_address(source),", t.length_storage, ")){\n"); }
    else if operation == 1 { out.format("uint64_t tag=g_read_length(image,", t.length_storage, ");image+=", t.length_storage, ";switch(tag){\n"); }
    else if operation == 2 { out.format("uint64_t tag=g_read_length(g_address(source),", t.length_storage, ");g_write_length(image,", t.length_storage, ",tag);image+=", t.length_storage, ";switch(tag){\n"); }
    else {
        out.format("uint64_t tag=g_read_length(image,", t.length_storage, ");g_write_length(g_address(dest),", t.length_storage, ",tag);image+=", t.length_storage, ";\n");
        if cc_region_width(p, id) > 0 {
            out.format("GRegion *region=((g_t", id, "*)g_address(dest))->region;g_init_", id, "(dest,region-g_regions);\n");
        }
        out.append("switch(tag){\n");
    }
    var variant = p.nodes[t.declaration].first;
    while variant >= 0 {
        let payload = p.nodes[variant].type_id;
        out.format("case ", p.nodes[variant].integer, ":");
        if operation == 0 { out.format("size=g_image_add(size,g_image_size_", payload, "(g_offset(source,", t.length_storage, ")));break;\n"); }
        else if operation == 1 { out.format("image=g_image_skip_", payload, "(image);break;\n"); }
        else if operation == 2 { out.format("image=g_image_write_", payload, "(image,g_offset(source,", t.length_storage, "));break;\n"); }
        else { out.format("image=g_image_unpack_", payload, "(g_offset(dest,", t.length_storage, "),image);break;\n"); }
        variant = p.nodes[variant].next;
    }
    out.append("default:g_panic(\"corrupt ADT tag\");}\n");
    if fixed {
        if operation == 0 { out.format("return ", t.size, ";\n"); }
        else { out.format("return start+", t.size, ";\n"); }
    } else if operation == 0 { out.append("return size;\n"); }
    else { out.append("return image;\n"); }
}
fn ci_emit_type(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; let direct = ci_direct(p, id);
    for operation in 0..4 {
        if operation == 0 { out.format("static int64_t g_image_size_", id, "(GRef source){\n"); }
        else if operation == 1 { out.format("static const uint8_t *g_image_skip_", id, "(const uint8_t *image){const uint8_t *start=image;\n"); }
        else if operation == 2 { out.format("static uint8_t *g_image_write_", id, "(uint8_t *image,GRef source){uint8_t *start=image;\n"); }
        else { out.format("static const uint8_t *g_image_unpack_", id, "(GRef dest,const uint8_t *image){const uint8_t *start=image;\n"); }
        if cc_image_type(p, id) && operation != 1 {
            if operation == 0 { out.append("GImage value;memcpy(&value,g_address(source),sizeof value);return g_image_span(value);\n"); }
            else if operation == 2 { out.append("GImage value;memcpy(&value,g_address(source),sizeof value);int64_t bytes=g_image_span(value);if(bytes)memmove(image,value.base,(size_t)bytes);return image+bytes;\n"); }
            else { out.format("const uint8_t *end=g_image_skip_", id, "(image);g_image_copy_into(dest,(GImage){(uint8_t*)image,(uint8_t*)end,NULL});return end;\n"); }
        } else if direct {
            let bytes = cc_frame_size(p, id);
            if operation == 0 { out.format("return ", bytes, ";\n"); }
            else if operation == 1 { out.format("return image+", bytes, ";\n"); }
            else if operation == 2 { if bytes > 0 { out.format("memcpy(image,g_address(source),", bytes, ");"); } out.format("return image+", bytes, ";\n"); }
            else { if bytes > 0 { out.format("memcpy(g_address(dest),image,", bytes, ");"); } out.format("return image+", bytes, ";\n"); }
        } else if t.kind == TY_REF {
            if t.length_storage >= 0 { out.append("g_panic(\"relative value requires its containing image\");"); if operation == 0 { out.append("return 0;\n"); } else { out.append("return image;\n"); } }
            else if operation == 0 { out.append("return 8;\n"); }
            else if operation == 1 { out.append("return image+8;\n"); }
            else if operation == 2 {
                if (t.flags & TF_CONST) == 0 && (p.types[t.element].flags & TF_CONST) == 0 { out.append("GRef value;memcpy(&value,g_address(source),8);if(value)g_panic(\"mutable reference cannot enter a transfer image\");\n"); }
                out.append("memcpy(image,g_address(source),8);return image+8;\n");
            } else { out.append("memcpy(g_address(dest),image,8);return image+8;\n"); }
        } else if t.kind == TY_INT && t.storage == 1 {
            if operation == 0 { out.append("int64_t value;memcpy(&value,g_address(source),8);return g_image_uleb_width(((uint64_t)value<<1)^(uint64_t)(value>>63));\n"); }
            else if operation == 1 { out.append("return image+gs_uleb_size(image);\n"); }
            else if operation == 2 { out.append("int64_t value;memcpy(&value,g_address(source),8);return image+gs_zig_write(image,value);\n"); }
            else { out.append("int64_t value=gs_zig_read(image);memcpy(g_address(dest),&value,8);return image+gs_uleb_size(image);\n"); }
        } else if t.kind == TY_ARRAY || t.kind == TY_SLICE {
            ci_array_header(p, out, id, operation);
            if operation == 0 {
                if t.kind == TY_ARRAY && t.array_kind == A_LIMITED { out.format("return g_image_add(size,g_image_product(slots,", p.types[t.element].size, "));\n"); }
                else { out.format("for(int64_t i=0;i<slots;i++)size=g_image_add(size,g_image_size_", t.element, "("); ci_element(p, out, id, "source"); out.append("));return size;\n"); }
            } else if operation == 1 {
                if t.kind == TY_ARRAY && t.array_kind == A_LIMITED { out.format("return image+slots*", p.types[t.element].size, ";\n"); }
                else { out.format("for(int64_t i=0;i<slots;i++)image=g_image_skip_", t.element, "(image);return image;\n"); }
            }
            else if operation == 2 {
                out.append("for(int64_t i=0;i<"); if t.kind == TY_ARRAY && t.array_kind == A_LIMITED { out.append("count"); } else { out.append("slots"); }
                out.format(";i++)image=g_image_write_", t.element, "(image,"); ci_element(p, out, id, "source"); out.append(");\n");
                if t.kind == TY_ARRAY && t.array_kind == A_LIMITED {
                    out.append("if(slots>count){memcpy(image,g_image_data(source,"); ci_array_args(p, out, id); out.format(")+count*", cc_frame_size(p, t.element), ",(size_t)(slots-count)*", p.types[t.element].size, ");image+=(slots-count)*", p.types[t.element].size, ";}\n");
                }
                out.append("return image;\n");
            } else {
                if t.kind == TY_ARRAY && (t.array_kind == A_GROW || t.array_kind == A_GROWSHRINK) {
                    out.append("g_reserve(dest,"); ci_array_args(p, out, id); out.format(",", cc_frame_size(p, t.element), ",count);\n");
                    out.append("GArray value;memcpy(&value,g_address(dest),sizeof value);uint8_t *data=value.data;\n");
                } else if t.kind == TY_ARRAY && (t.array_kind == A_FIXED || t.array_kind == A_LIMITED && t.count >= 0) {
                    out.append("uint8_t *data=g_address(dest);"); if t.array_kind == A_LIMITED { out.format("data+=", ci_prefix(p, id), ";"); } out.append("\n");
                } else {
                    out.format("uint8_t *data=g_alloc((size_t)g_image_product(slots,", cc_frame_size(p, t.element), "));\n");
                }
                out.append("for(int64_t i=0;i<"); if t.kind == TY_ARRAY && t.array_kind == A_LIMITED { out.append("count"); } else { out.append("slots"); }
                out.format(";i++)image=g_image_unpack_", t.element, "(g_ref(data+i*", cc_frame_size(p, t.element), "),image);\n");
                if t.kind == TY_ARRAY && t.array_kind == A_LIMITED { out.format("if(slots>count){memcpy(data+count*", cc_frame_size(p, t.element), ",image,(size_t)(slots-count)*", p.types[t.element].size, ");image+=(slots-count)*", p.types[t.element].size, ";}\n"); }
                if t.kind == TY_SLICE { out.append("GSlice value={g_ref(data),count};memcpy(g_address(dest),&value,sizeof value);\n"); }
                else if t.array_kind == A_VAR || t.array_kind == A_LIMITED && t.count < 0 { out.append("GArray value={data,count,{.cap=slots}};memcpy(g_address(dest),&value,sizeof value);\n"); }
                else if t.array_kind != A_FIXED { out.append("g_set_len(dest,"); ci_array_args(p, out, id); out.append(",count);\n"); }
                out.append("return image;\n");
            }
        } else if t.kind == TY_STRUCT || t.kind == TY_TUPLE {
            if operation == 0 { out.append("int64_t size=0;\n"); }
            ci_fields(p, out, id, operation);
            if operation == 0 { out.append("return size;\n"); } else { out.append("return image;\n"); }
        } else if t.kind == TY_ENUM { ci_enum(p, out, id, operation); }
        else {
            out.append("g_panic(\"type has no transfer image\");");
            if operation == 0 { out.append("return 0;\n"); } else { out.append("return image;\n"); }
        }
        out.append("}\n");
    }
    if cc_image_type(p, id) {
        out.format("static const uint8_t *g_image_read_", id, "(GRef dest,const uint8_t *image,int64_t region_base){return g_image_unpack_", id, "(dest,image);}\n"); return;
    }
    out.format("static const uint8_t *g_image_read_", id, "(GRef dest,const uint8_t *image,int64_t region_base){\n",
        "const uint8_t *end=g_image_skip_", id, "(image);int64_t bytes=end-image;\n",
        "const uint8_t *copy=g_image_copy(image,bytes,region_base);g_image_unpack_", id, "(dest,copy);return end;}\n");
}
fn cc_image_emit(p: Program&, out: u8[>..]&, used: const bool[:]) {
    cc_index_lengths(p, out);
    for t, id in p.types {
        if !used[id] || !cc_concrete(p, id) { continue; }
        if ci_verifiable(p, id) { out.format("static const uint8_t *g_image_check_", id, "(const uint8_t*,const uint8_t*);\n"); }
        out.format("static int64_t g_image_size_", id, "(GRef);\n",
            "static const uint8_t *g_image_skip_", id, "(const uint8_t*);\n",
            "static uint8_t *g_image_write_", id, "(uint8_t*,GRef);\n",
            "static const uint8_t *g_image_unpack_", id, "(GRef,const uint8_t*);\n",
            "static const uint8_t *g_image_read_", id, "(GRef,const uint8_t*,int64_t);\n");
    }
    for t, id in p.types { if used[id] && cc_concrete(p, id) { ci_emit_type(p, out, id); ci_verify_type(p, out, id); } }
}

recursive fn ci_verifiable(p: Program&, id: i64) -> bool {
    let t = p.types[id];
    if t.storage != 0 { return false; }
    if t.kind == TY_INT { return t.index_type < 0 || ci_index_global(p, id); }
    if t.kind == TY_BOOL || t.kind == TY_FLOAT { return true; }
    if t.kind == TY_ARRAY {
        return (t.array_kind == A_FIXED || t.array_kind == A_VAR || t.array_kind == A_LIMITED) && ci_verifiable(p, t.element);
    }
    if t.kind == TY_STRUCT || t.kind == TY_TUPLE {
        var field = t.first; if t.kind == TY_STRUCT { field = p.nodes[t.declaration].first; }
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 && !ci_verifiable(p, p.nodes[field].type_id) { return false; }
            field = p.nodes[field].next;
        }
        return true;
    }
    if t.kind == TY_ENUM && t.length_storage > 0 {
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let child = p.nodes[variant].type_id;
            if !ci_verifiable(p, child) || (t.flags & F_VARIABLE_MODE) == 0 && !ci_direct(p, child) { return false; }
            variant = p.nodes[variant].next;
        }
        return true;
    }
    return false;
}
recursive fn ci_min_bytes(p: Program&, id: i64) -> i64 {
    let t = p.types[id];
    if t.kind == TY_ARRAY {
        if t.array_kind == A_FIXED { return t.count * ci_min_bytes(p, t.element); }
        if t.array_kind == A_LIMITED { if t.count < 0 { return 8; } return ci_prefix(p, id) + t.count * ci_min_bytes(p, t.element); }
        if t.length_storage > 0 { return t.length_storage; } return 1;
    }
    if t.kind == TY_STRUCT || t.kind == TY_TUPLE {
        var field = t.first; if t.kind == TY_STRUCT { field = p.nodes[t.declaration].first; }
        var size = 0;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) != 0 { size += p.nodes[field].aux; }
            else { size += ci_min_bytes(p, p.nodes[field].type_id); }
            field = p.nodes[field].next;
        }
        return size;
    }
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) != 0 {
        var minimum = -1; var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let bytes = ci_min_bytes(p, p.nodes[variant].type_id);
            if minimum < 0 || bytes < minimum { minimum = bytes; } variant = p.nodes[variant].next;
        }
        return t.length_storage + minimum;
    }
    return t.size;
}
fn ci_verify_type(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !ci_verifiable(p, id) { return; }
    out.format("static const uint8_t *g_image_check_", id, "(const uint8_t *image,const uint8_t *end){\n");
    if t.kind == TY_BOOL { out.append("if(image==end || *image>1)return NULL;return image+1;\n"); }
    else if t.kind == TY_INT || t.kind == TY_FLOAT {
        out.format("if(end-image<", t.size, ")return NULL;\n");
        if t.kind == TY_INT && t.index_type >= 0 {
            out.format("uint64_t value=0;memcpy(&value,image,", t.size, ");if(value");
            if (t.flags & F_BOUND_TYPE) != 0 { out.append(">"); } else { out.append(">="); }
            out.format("(uint64_t)g_image_bound_", t.pool, "())return NULL;\n");
        }
        out.format("return image+", t.size, ";\n");
    }
    else if t.kind == TY_STRUCT || t.kind == TY_TUPLE {
        var field = t.first; if t.kind == TY_STRUCT { field = p.nodes[t.declaration].first; }
        while field >= 0 {
            let n = p.nodes[field];
            if (n.flags & F_PAD) != 0 { out.format("if(end-image<", n.aux, ")return NULL;image+=", n.aux, ";\n"); }
            else { out.format("image=g_image_check_", n.type_id, "(image,end);if(!image)return NULL;\n"); }
            field = n.next;
        }
        out.append("return image;\n");
    } else if t.kind == TY_ENUM {
        if (t.flags & F_VARIABLE_MODE) == 0 { out.format("if(end-image<", t.size, ")return NULL;const uint8_t *limit=image+", t.size, ";\n"); }
        out.format("int64_t tag;image=g_image_count_check(image,end,", t.length_storage, ",&tag);if(!image)return NULL;switch(tag){\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            out.format("case ", p.nodes[variant].integer, ":image=g_image_check_", p.nodes[variant].type_id, "(image,");
            if (t.flags & F_VARIABLE_MODE) == 0 { out.append("limit"); } else { out.append("end"); } out.append(");break;\n"); variant = p.nodes[variant].next;
        }
        out.append("default:return NULL;}if(!image)return NULL;\n");
        if (t.flags & F_VARIABLE_MODE) == 0 { out.append("return limit;\n"); } else { out.append("return image;\n"); }
    } else if t.kind == TY_ARRAY {
        if t.array_kind == A_FIXED { out.format("int64_t count=", t.count, ";\n"); }
        else {
            if t.array_kind == A_LIMITED && t.count < 0 { out.append("int64_t slots;image=g_image_count_check(image,end,4,&slots);if(!image)return NULL;\n"); }
            var prefix = ci_prefix(p, id); if t.array_kind == A_LIMITED && t.count < 0 { prefix = 4; }
            out.format("int64_t count;image=g_image_count_check(image,end,", prefix, ",&count);if(!image)return NULL;\n");
            if t.array_kind == A_LIMITED {
                if t.count >= 0 { out.format("int64_t slots=", t.count, ";\n"); }
                var stride = p.types[t.element].size; if stride < 1 { stride = 1; }
                out.format("if(count>slots || slots>(end-image)/", stride, ")return NULL;const uint8_t *limit=image+slots*", p.types[t.element].size, ";\n");
            }
        }
        var minimum = ci_min_bytes(p, t.element); if minimum < 1 { minimum = 1; }
        if t.array_kind == A_VAR { out.format("if(count>(end-image)/", minimum, ")return NULL;\n"); }
        out.format("for(int64_t i=0;i<count;i++){image=g_image_check_", t.element, "(image,end);if(!image)return NULL;}\n");
        if t.array_kind == A_LIMITED { out.append("return limit;\n"); } else { out.append("return image;\n"); }
    }
    out.append("}\n");
}

fn ci_index_global(p: Program&, id: i64) -> bool {
    let t = p.types[id]; return t.index_type >= 0 && t.pool >= 0 && t.pool < p.symbols.len && (p.symbols[t.pool].flags & S_GLOBAL) != 0;
}
fn cc_index_lengths(p: Program&, out: u8[>..]&, definitions: bool = false) {
    var seen: bool[>..] = []; seen.resize(p.symbols.len, false);
    for t, id in p.types {
        if t.kind != TY_INT || !ci_index_global(p, id) || seen[t.pool] { continue; } seen[t.pool] = true;
        out.format("static int64_t g_image_bound_", t.pool, "(void)");
        if !definitions { out.append(";\n"); continue; }
        out.format("{GRef base=g_ref(&g_s", t.pool, ");\n"); var array = p.symbols[t.pool].type_id;
        while cc_kind(p, array) == TY_REF { out.append("memcpy(&base,g_address(base),sizeof base);\n"); array = p.types[array].element; }
        out.append("return g_len(base,"); ci_array_args(p, out, array); out.append(");}\n");
    }
}

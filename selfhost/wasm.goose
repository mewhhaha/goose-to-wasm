// Deterministic WebAssembly binary encoding. This module has no assembler,
// native compiler, filesystem, or process dependency.

// Share byte and integer writers across Wasm emitters.
inline fn wb_byte(out: u8[>..]&, value: i64) { out.push((value & 255) as u8); }

fn wb_u(out: u8[>..]&, value: i64) {
    if (value as! u64) < 128 { out.push(value as u8); return; }
    if (value as! u64) < 16384 { wb_pair(out, ((value & 127) | 128) as u8, (value >> 7) as u8); return; }
    var remaining = value as! u64;
    loop {
        var byte = (remaining & 127) as u8;
        remaining = remaining >> 7;
        if remaining != 0 { byte = byte | 128; }
        out.push(byte);
        if remaining == 0 { return; }
    }
}

fn wb_s(out: u8[>..]&, value: i64) {
    if value >= -64 && value < 64 { out.push((value & 127) as u8); return; }
    if value >= -8192 && value < 8192 { wb_pair(out, ((value & 127) | 128) as u8, ((value >> 7) & 127) as u8); return; }
    var remaining = value;
    loop {
        let byte = remaining & 127;
        remaining = remaining >> 7;
        let done = (remaining == 0 && (byte & 64) == 0) ||
                   (remaining == -1 && (byte & 64) != 0);
        if done { out.push(byte as u8); return; }
        out.push((byte | 128) as u8);
    }
}

fn wb_raw(out: u8[>..]&, bytes: u8[:]) {
    out.append(bytes);
}

fn wb_name(out: u8[>..]&, name: u8[:]) {
    wb_u(out, name.len);
    wb_raw(out, name);
}

fn wb_section(out: u8[>..]&, kind: i64, payload: u8[:]) {
    wb_byte(out, kind);
    wb_u(out, payload.len);
    wb_raw(out, payload);
}

inline fn wb_u_width(value: i64) -> i64 {
    if (value as! u64) < 128 { return 1; }
    if (value as! u64) < 16384 { return 2; }
    var width = 2; var rest = (value as! u64) >> 14;
    while rest != 0 { width++; rest >>= 7; }
    return width;
}
inline fn wb_s_width(value: i64) -> i64 {
    if value >= -64 && value < 64 { return 1; }
    if value >= -8192 && value < 8192 { return 2; }
    var width = 3; var rest = value >> 14;
    while rest < -64 || rest >= 64 { width++; rest >>= 7; }
    return width;
}
fn wb_counted_section_header(out: u8[>..]&, kind: i64, count: i64, payload_len: i64) {
    wb_byte(out, kind);
    wb_u(out, payload_len + wb_u_width(count));
    wb_u(out, count);
}
inline fn wb_slice_u(out: u8[:], at: i64&, value: i64) {
    var remaining = value as! u64;
    while remaining >= 128 {
        out[at] = ((remaining & 127) | 128) as u8; at++; remaining >>= 7;
    }
    out[at] = remaining as u8; at++;
}
inline fn wb_slice_s(out: u8[:], at: i64&, value: i64) {
    var remaining = value;
    while remaining < -64 || remaining >= 64 {
        out[at] = ((remaining & 127) | 128) as u8; at++; remaining >>= 7;
    }
    out[at] = (remaining & 127) as u8; at++;
}

inline fn wb_pair(out: u8[>..]&, first: u8, second: u8) {
    let bytes: u8[2] = [first, second];
    out.append(bytes);
}
inline fn wb_triplet(out: u8[>..]&, first: u8, second: u8, third: u8) {
    let bytes: u8[3] = [first, second, third];
    out.append(bytes);
}
inline fn wb_op(out: u8[>..]&, opcode: i64, argument: i64) {
    let op = (opcode & 255) as u8;
    if (argument as! u64) < 128 { wb_pair(out, op, argument as u8); }
    else if (argument as! u64) < 16384 { wb_triplet(out, op, ((argument & 127) | 128) as u8, (argument >> 7) as u8); }
    else { out.push(op); wb_u(out, argument); }
}
fn wb_signed_op(out: u8[>..]&, opcode: u8, value: i64) {
    if value >= -8192 && value < 8192 {
        wb_triplet(out, opcode, ((value & 127) | 128) as u8, ((value >> 7) & 127) as u8);
    } else {
        var bytes: u8[11] = [0; 11];
        bytes[0] = opcode;
        var at = 1;
        wb_slice_s(bytes, at, value);
        out.append(bytes[..at]);
    }
}
inline fn wb_i32(out: u8[>..]&, value: i64) {
    // Wasm's i32 immediate is signed even when its value is an address.
    let v = (value as! u32) as! i32;
    if v >= -64 && v < 64 { wb_pair(out, 0x41, (v & 127) as u8); }
    else { wb_signed_op(out, 0x41, v); }
}
inline fn wb_i64(out: u8[>..]&, value: i64) {
    if value >= -64 && value < 64 { wb_pair(out, 0x42, (value & 127) as u8); }
    else { wb_signed_op(out, 0x42, value); }
}

fn wb_f32(out: u8[>..]&, value: f64) {
    wb_byte(out, 0x43);
    let values: f32[1] = [value as f32];
    let bytes = bytes_of(values);
    wb_raw(out, bytes);
}

fn wb_f64(out: u8[>..]&, value: f64) {
    wb_byte(out, 0x44);
    let values: f64[1] = [value];
    let bytes = bytes_of(values);
    wb_raw(out, bytes);
}

inline fn wb_mem(out: u8[>..]&, opcode: i64, alignment: i64, offset: i64) {
    let op = (opcode & 255) as u8;
    let align = (alignment & 127) as u8;
    if (offset as! u64) < 128 { wb_triplet(out, op, align, offset as u8); }
    else { wb_pair(out, op, align); wb_u(out, offset); }
}

fn wb_signature(out: u8[>..]&, args: u8[:], results: u8[:]) {
    wb_byte(out, 0x60);
    wb_u(out, args.len);
    wb_raw(out, args);
    wb_u(out, results.len);
    wb_raw(out, results);
}

fn wb_import(out: u8[>..]&, module: u8[:], name: u8[:], signature: i64) {
    wb_name(out, module);
    wb_name(out, name);
    wb_byte(out, 0);
    wb_u(out, signature);
}

fn wb_export(out: u8[>..]&, name: u8[:], kind: i64, index: i64) {
    wb_name(out, name);
    wb_byte(out, kind);
    wb_u(out, index);
}

fn wb_copy(out: u8[>..]&) {
    let bytes: u8[4] = [0xfc, 10, 0, 0];
    out.append(bytes);
}
fn wb_fill(out: u8[>..]&) { wb_triplet(out, 0xfc, 11, 0); }
fn wb_body(out: u8[>..]&, locals: i64[:], code: u8[:]) {
    var groups = 0; var previous = -1;
    for kind in locals { if kind != previous { groups++; previous = kind; } }
    wb_u(out, groups); var at = 0;
    while at < locals.len {
        let kind = locals[at]; var end = at + 1;
        while end < locals.len && locals[end] == kind { end++; }
        wb_u(out, end - at); wb_byte(out, kind); at = end;
    }
    wb_raw(out, code);
}

struct WbInstruction { start: i64, end: i64, opcode: i64, index: i64 = -1, omitted: bool = false }
inline fn wb_read_unsigned(bytes: u8[:], at: i64&) -> i64 {
    var value: i64 = 0; var shift = 0;
    loop {
        let byte = bytes[at]; at++;
        value |= ((byte as i64) & 127) << shift;
        if (byte & 128) == 0 { return value; } shift += 7;
    }
}
inline fn wb_skip_leb(bytes: u8[:], at: i64&) {
    loop { let byte = bytes[at]; at++; if (byte & 128) == 0 { return; } }
}
fn wb_read_operands(bytes: u8[:], at: i64&, opcode: i64) -> i64 {
    // Only branch depths and local indexes participate in local allocation.
    if opcode == 0x0c || opcode == 0x0d || opcode >= 0x20 && opcode <= 0x22 { return wb_read_unsigned(bytes, at); }
    if opcode >= 0x02 && opcode <= 0x04 || opcode == 0x10 || opcode == 0x23 || opcode == 0x24 || opcode == 0x3f || opcode == 0x40 { wb_skip_leb(bytes, at); }
    else if opcode == 0x0e { let count = wb_read_unsigned(bytes, at); for i in 0..count + 1 { wb_skip_leb(bytes, at); } }
    else if opcode == 0x11 { wb_skip_leb(bytes, at); wb_skip_leb(bytes, at); }
    else if opcode >= 0x28 && opcode <= 0x3e { wb_skip_leb(bytes, at); wb_skip_leb(bytes, at); }
    else if opcode == 0x41 || opcode == 0x42 { wb_skip_leb(bytes, at); }
    else if opcode == 0x43 { at += 4; } else if opcode == 0x44 { at += 8; }
    else if opcode == 0x1c { let count = wb_read_unsigned(bytes, at); at += count; }
    else if opcode == 0xfc {
        let sub = wb_read_unsigned(bytes, at);
        if sub == 8 || sub == 10 { wb_skip_leb(bytes, at); wb_skip_leb(bytes, at); }
        else if sub == 9 || sub == 11 { wb_skip_leb(bytes, at); }
    } else if opcode == 0xfd {
        // SIMD: a memory operand, sixteen bytes, a lane, or nothing.
        let sub = wb_read_unsigned(bytes, at);
        if sub <= 0x0b || sub == 0x5c || sub == 0x5d { wb_skip_leb(bytes, at); wb_skip_leb(bytes, at); }
        else if sub == 0x0c || sub == 0x0d { at += 16; }
        else if sub >= 0x15 && sub <= 0x22 { at += 1; }
        else if sub >= 0x54 && sub <= 0x5b { wb_skip_leb(bytes, at); wb_skip_leb(bytes, at); at += 1; }
    }
    return -1;
}
fn wb_compact_body(out: u8[>..]&, locals: i64[:], code: u8[:], params: i64) {
    var instructions: WbInstruction[>..] = []; var at = 0;
    while at < code.len {
        let start = at; let op = code[at] as i64; at++;
        let index = wb_read_operands(code, at, op);
        instructions.push(WbInstruction { start: start, end: at, opcode: op, index: index });
    }
    // Complete instruction boundaries are mandatory: immediates can contain
    // the same bytes as local.set/get. This is the pinned writer's peephole.
    at = 0;
    while at + 1 < instructions.len {
        let left = instructions[at]; let right = instructions[at + 1];
        if left.opcode == 0x21 && right.opcode == 0x20 && left.index == right.index {
            instructions[at].opcode = 0x22; instructions[at + 1].omitted = true; at += 2;
        } else { at++; }
    }
    var read: bool[>..] = []; var remap: i64[>..] = []; var kept: i64[>..] = []; var encoded: u8[>..] = [];
    for i in 0..params + locals.len { read.push(false); remap.push(i); }
    for instruction in instructions { if !instruction.omitted && instruction.opcode == 0x20 { read[instruction.index] = true; } }
    for kind, i in locals {
        if read[params + i] { remap[params + i] = params + kept.len; kept.push(kind); }
    }
    for instruction in instructions {
        if instruction.omitted { continue; }
        if instruction.opcode >= 0x20 && instruction.opcode <= 0x22 {
            if read[instruction.index] { wb_op(encoded, instruction.opcode, remap[instruction.index]); }
            else if instruction.opcode == 0x21 { wb_byte(encoded, 0x1a); }
        } else { wb_raw(encoded, code[instruction.start..instruction.end]); }
    }
    wb_body(out, kept, encoded);
}

// An event is a non-parameter local access or control instruction. Its
// offset is relative to the emitted body or prelude. Branch table targets
// stay in the bytecode.
struct WbEvent { start: i32, operand: i32, opcode: u8 }

// A block, loop or if being read by wb_reuse_body: where it began (a loop),
// where its definite assignments start on the undo stack, and whether a
// branch names it.
struct WbFrame { at: i32, looping: bool = false, conditional: bool = false, alternative: bool = false, branched: bool = false, undo: i32 = 0 }
// Gives locals whose values are never live at once the same index. The
// backend makes a local for every temporary (cg_save), thousands in a large
// function, and a baseline compiler gives each a stack slot.
//
// A local's span is from its first to its last instruction. Two locals may
// share an index if their spans do not meet, with two corrections that make
// a span cover every instruction its value can be needed at:
// - a read not dominated by a write (it may read the zero a local starts
//   with) starts the span at the function's start;
// - a read inside a loop of a value written before the loop, or not
//   certainly written on this iteration, makes the span cover the loop.
// A write dominates a later read in the same block or one nested in it; a
// local written in both arms of an if that no branch names is written after
// it. Everything else is taken as not written, which only costs sharing.
// Reusable scratch buffers for wb_reuse_body so per-function emission avoids
// acquiring fresh growable regions on every function body.
struct WbReuseScratch {
    first: i32[>..]&, last: i32[>..]&, written: i32[>..]&, arm: i32[>..]&, stamp: i32[>..]&,
    loop_end: i32[>..]&, active_loops: i32[>..]&,
    frames: WbFrame[>..]&, undo: i32[>..]&, covers: i32[>..]&,
    head: i32[>..]&, next: i32[>..]&, kinds: i64[>..]&, ends: i32[>..]&,
    reads: i32[>..]&, action: u8[>..]&,
    epoch: i32 = 1,
}

inline fn wb_local_len(index: i64) -> i64 {
    if index < 128 { return 2; }
    if index < 16384 { return 3; }
    var length = 2;
    var remaining = index >> 7;
    while remaining > 0 { length++; remaining >>= 7; }
    return length;
}

inline fn wb_patch_local_index(bytes: u8[:], start: i64, index: i64, width: i64) {
    var remaining = index;
    for offset in 0..width - 1 {
        bytes[start + offset] = ((remaining & 127) | 128) as u8;
        remaining >>= 7;
    }
    bytes[start + width - 1] = remaining as u8;
}

// Offset of a deferred immediate, relative to the byte stream currently
// being copied. The request number is stable through every body rewrite.
struct CgFixup { raw_off: i64, dummy_len: u8, req_idx: i64, enc_kind: u8 }

inline fn wb_relocate_fixups(fixups: CgFixup[:], next: i64&, limit: i64, delta: i64) {
    while next < fixups.len && fixups[next].raw_off < limit {
        fixups[next].raw_off += delta;
        next++;
    }
}
inline fn wb_copy_body_run(out: u8[>..]&, bytes: u8[:], start: i64, end: i64, fixups: CgFixup[:], next: i64&) {
    if start >= end { return; }
    if next < fixups.len { wb_relocate_fixups(fixups, next, end, out.len - start); }
    wb_raw(out, bytes[start..end]);
}

fn wb_reuse_body(out: u8[>..]&, locals: i64[>..]&, code: u8[>..]&, params: i64, events: WbEvent[:], body_event_count: i64, prelude_bytes: i64, no_regions: bool, s: WbReuseScratch&, fixups: CgFixup[:]) {
    var next_fixup = 0;
    if locals.len == 0 {
        wb_body(out, locals, code);
        wb_relocate_fixups(fixups, next_fixup, code.len, out.len - code.len);
        return;
    }
    let total = params + locals.len;
    if s.epoch > 1000000000 {
        s.arm.clear(); s.stamp.clear(); s.epoch = 1;
    }
    let epoch = s.epoch;
    if s.first.len < total { s.first.resize(total, -1); }
    if s.last.len < total { s.last.resize(total, -1); }
    if s.written.len < total { s.written.resize(total, 0); }
    if s.arm.len < total { s.arm.resize(total, 0); }
    if s.stamp.len < total { s.stamp.resize(total, 0); }
    if s.next.len < total { s.next.resize(total, -1); }
    if s.undo.len < total { s.undo.resize(total, 0); }
    if s.ends.len < total { s.ends.resize(total, 0); }
    if s.reads.len < total { s.reads.resize(total, 0); }
    // Ensure loop_end, head, and action have room for all event positions without shrinking.
    let max_pos = events.len + 2;
    if s.loop_end.len < max_pos { s.loop_end.resize(max_pos, -1); }
    if s.head.len < max_pos { s.head.resize(max_pos, -1); }
    if s.action.len < events.len { s.action.resize(events.len, 0); }
    s.covers.clear();
    var frame_len: i64 = 0; var loop_depth: i64 = 0;
    let bytes: u8[:] = code;
    let first: i32[:] = s.first[0..total];
    let reads: i32[:] = s.reads[0..total];
    for i in params..total { first[i] = -1; reads[i] = 0; }
    let last: i32[:] = s.last[0..total];
    let written: i32[:] = s.written[0..total];
    let arm: i32[:] = s.arm[0..total];
    let stamp: i32[:] = s.stamp[0..total];
    let undo: i32[:] = s.undo[0..total];
    let ends: i32[:] = s.ends[0..total];
    let loop_end: i32[:] = s.loop_end[0..max_pos];
    let action: u8[:] = s.action[0..events.len];
    // Action codes: 0 = keep, 1 = local.set -> local.tee, 2 = omit, 3 = local.set -> drop.
    // Fuse action zeroing, optional no_regions folding, and Pass 0 read counting into one scan.
    var any_folded = false;
    if no_regions {
        // When the function never acquires a data region, any cg_restore_regions
        // (local.get mark; global.set 3) is dead; omitting it lets pass 2 drop the mark too.
        for segment in 0..2 {
            var first_event = body_event_count; var limit = events.len;
            if segment != 0 { first_event = 0; limit = body_event_count; }
            var ei = first_event;
            while ei < limit {
                let e1: const WbEvent& = events[ei];
                let op1 = e1.opcode as i64;
                if op1 == 0x20 && ei + 1 < limit {
                    let e2: const WbEvent& = events[ei + 1];
                    if (e2.opcode as i64) == 0x24 && (e2.operand as i64) == 3 &&
                       (e1.start as i64) + wb_local_len(e1.operand as i64) == (e2.start as i64) {
                        action[ei] = 2; action[ei + 1] = 2;
                        any_folded = true;
                        ei += 2;
                        continue;
                    }
                }
                action[ei] = 0;
                if op1 == 0x20 { reads[e1.operand as i64]++; }
                ei++;
            }
        }
    } else {
        for event_index in 0..events.len {
            action[event_index] = 0;
            let event: const WbEvent& = events[event_index];
            if (event.opcode as i64) == 0x20 { reads[event.operand as i64]++; }
        }
    }
    // Peephole pass 1: fold adjacent (including nested) local.set L; local.get L
    // pairs into empty (when L has only this read) or local.tee L (when L has more reads).
    for segment in 0..2 {
        var first_event = body_event_count; var limit = events.len;
        if segment != 0 { first_event = 0; limit = body_event_count; }
        var stack_len: i64 = 0;
        var chain_end: i64 = -1;
        for ei in first_event..limit {
            if (action[ei] as i64) == 2 { continue; }
            let e: const WbEvent& = events[ei];
            let estart = e.start as i64;
            if stack_len > 0 && estart != chain_end { stack_len = 0; }
            let op = e.opcode as i64;
            if op == 0x21 {
                loop_end[stack_len] = ei as i32;
                stack_len++;
                chain_end = estart + wb_local_len(e.operand as i64);
            } else if op == 0x20 && stack_len > 0 {
                let top_ei = loop_end[stack_len - 1] as i64;
                let loc = e.operand as i64;
                if (events[top_ei].operand as i64) == loc {
                    if reads[loc] == 1 {
                        action[top_ei] = 2; action[ei] = 2; reads[loc] = 0;
                        stack_len--;
                        chain_end = estart + wb_local_len(loc);
                    } else {
                        action[top_ei] = 1; action[ei] = 2; reads[loc]--;
                        stack_len = 0;
                    }
                    any_folded = true;
                } else {
                    stack_len = 0;
                }
            } else {
                stack_len = 0;
            }
        }
    }
    // Dead writes and span discovery share a pass. The preceding global.get
    // of an omitted write is ignored by span discovery regardless of action.
    var undo_len: i64 = 0;
    // The first instruction may have no event (typically global.get in
    // the prelude). Keep its position for implicitly zeroed locals.
    var position: i32 = -1;
    if prelude_bytes > 0 {
        if body_event_count == events.len || events[body_event_count].start != 0 { position = 0; }
    } else if bytes.len > 0 && (body_event_count == 0 || events[0].start != 0) { position = 0; }
    for segment in 0..2 {
        var first_event = body_event_count; var limit = events.len; var base = 0;
        if segment != 0 { first_event = 0; limit = body_event_count; base = prelude_bytes; }
        for event_index in first_event..limit {
            let act = action[event_index];
            if act >= 2 { continue; }
            let event: const WbEvent& = events[event_index];
            let op = event.opcode as i64;
            if op >= 0x23 { continue; }
            let index = event.operand as i64;
            if op >= 0x20 && reads[index] == 0 {
                any_folded = true;
                action[event_index] = 2;
                if op == 0x21 && act == 0 {
                    action[event_index] = 3;
                    if event_index > first_event {
                        let prior: const WbEvent& = events[event_index - 1];
                        if prior.opcode == 0x23 && prior.start + wb_local_len(prior.operand) == event.start {
                            action[event_index - 1] = 2;
                            action[event_index] = 2;
                        }
                    }
                }
                continue;
            }
            position++;
            if op >= 0x20 {
                let local = index;
                if first[local] < 0 { first[local] = position; }
                last[local] = position;
                if op == 0x20 {
                    // The outermost loop entered since the write, or of all.
                    var depth = (written[local] as i64) - 1;
                    if depth < 0 { first[local] = 0; depth = 0; }
                    if depth < loop_depth {
                        let loop_at = s.active_loops[depth];
                        let tag = epoch + loop_at;
                        if stamp[local] != tag {
                            stamp[local] = tag; s.covers.push(local as i32); s.covers.push(loop_at);
                        }
                    }
                } else if written[local] == 0 {
                    written[local] = (loop_depth + 1) as i32;
                    undo[undo_len] = local as i32;
                    undo_len++;
                }
            } else if op == 0x0b {
                if frame_len == 0 { break; }
                frame_len--;
                let frame = s.frames[frame_len];
                let fmark = frame.undo as i64;
                let can_merge = frame.conditional && frame.alternative && !frame.branched;
                let tag = epoch + frame.at;
                if frame.looping {
                    loop_depth--;
                    loop_end[frame.at as i64] = position;
                }
                let new_depth = (loop_depth + 1) as i32;
                let undo_end = undo_len;
                undo_len = fmark;
                // Each local appears only once in the arm's undo range.
                for ui in fmark..undo_end {
                    let local = undo[ui] as i64;
                    if can_merge && arm[local] == tag {
                        written[local] = new_depth;
                        undo[undo_len] = local as i32;
                        undo_len++;
                    } else { written[local] = 0; }
                }
            } else if op == 0x02 || op == 0x03 || op == 0x04 {
                if op == 0x03 {
                    if loop_depth == s.active_loops.len { s.active_loops.push(position); }
                    else { s.active_loops[loop_depth] = position; }
                    loop_depth++;
                }
                let nf = WbFrame { at: position, looping: op == 0x03, conditional: op == 0x04, undo: undo_len as i32 };
                if frame_len == s.frames.len { s.frames.push(nf); } else { s.frames[frame_len] = nf; }
                frame_len++;
            } else if op == 0x05 {
                // The then arm ends: remember what it wrote, then forget it.
                let depth = frame_len - 1; let mark = s.frames[depth].undo as i64;
                let tag = epoch + s.frames[depth].at;
                for ui in mark..undo_len {
                    let loc = undo[ui] as i64;
                    arm[loc] = tag; written[loc] = 0;
                }
                undo_len = mark; s.frames[depth].alternative = true;
            } else if op == 0x0c || op == 0x0d {
                if index < frame_len { s.frames[frame_len - 1 - index].branched = true; }
            } else if op == 0x0e {
                var cursor = base + (event.start as i64) + 1; let count = wb_read_unsigned(bytes, cursor);
                for target in 0..count + 1 {
                    let label = wb_read_unsigned(bytes, cursor);
                    if label < frame_len { s.frames[frame_len - 1 - label].branched = true; }
                }
            }
        }
    }
    // Restore remaining top-level written entries to 0 for the next function.
    for ui in 0..undo_len { written[undo[ui] as i64] = 0; }
    s.epoch = epoch + position + 2;
    var pair = 0;
    while pair < s.covers.len {
        let local = s.covers[pair] as i64; let start = s.covers[pair + 1]; pair += 2;
        if start < first[local] { first[local] = start; }
        let lend = loop_end[start as i64];
        if lend > last[local] { last[local] = lend; }
    }
    // Take the locals in the order their spans start; give each the first
    // index of its type that is free again. s.head is kept at -1 between calls.
    let head_len = (position as i64) + 1;
    let head: i32[:] = s.head[0..head_len];
    let next: i32[:] = s.next[0..total];
    var local = total - 1;
    var max_first: i64 = -1;
    while local >= params {
        let fpos = first[local] as i64;
        if fpos >= 0 {
            if fpos > max_first { max_first = fpos; }
            next[local] = head[fpos]; head[fpos] = local as i32;
        }
        local--;
    }
    // Wasm groups slots by type in first-use order. Link each type's spans
    // in their original order so its first free slot can be found directly.
    s.kinds.clear();
    var begin: i32[8] = [-1; 8]; var tail: i32[8] = [-1; 8];
    for hi in 0..max_first + 1 {
        var member = head[hi] as i64;
        if member < 0 { continue; }
        head[hi] = -1;
        while member >= 0 {
            let following = next[member] as i64; let kind = locals[member - params];
            let slot = (0x7f - kind) & 7;
            if tail[slot] < 0 { s.kinds.push(kind); begin[slot] = member as i32; }
            else { next[tail[slot] as i64] = member as i32; }
            tail[slot] = member as i32; next[member] = -1; member = following;
        }
    }
    wb_u(out, s.kinds.len);
    var slot_count = 0;
    var changed = false;
    for kind in s.kinds {
        var ends_len: i64 = 0; var skip: i64 = 0; var until: i32 = -1;
        var member = begin[(0x7f - kind) & 7] as i64;
        let base_slot = params + slot_count;
        while member >= 0 {
            let start = first[member];
            if until < start { skip = 0; until = head_len as i32; }
            while skip < ends_len {
                let end = ends[skip];
                if end < start { break; }
                if end < until { until = end; }
                skip++;
            }
            if skip == ends_len {
                ends[ends_len] = last[member];
                ends_len++;
            } else { ends[skip] = last[member]; }
            // Once this span is placed, reuse its start slot for the final local index.
            let mapped = (base_slot + skip) as i32;
            first[member] = mapped;
            if mapped != member as i32 { changed = true; }
            member = next[member] as i64;
        }
        slot_count += ends_len;
        wb_u(out, ends_len); wb_byte(out, kind);
    }

    // Peephole pass 2: after slot reuse maps two locals to the same slot,
    // drop adjacent self-copies (`local.get X; local.set X`) and redundant
    // self-tees (`local.get X; local.tee X` -> `local.get X`).
    for segment in 0..2 {
        var first_event = body_event_count; var limit = events.len;
        if segment != 0 { first_event = 0; limit = body_event_count; }
        var prev_ei: i64 = -1;
        var prev_end: i64 = -1;
        for ei in first_event..limit {
            let act = action[ei] as i64;
            let e: const WbEvent& = events[ei];
            let estart = e.start as i64;
            let op = e.opcode as i64;
            if act == 2 {
                if prev_ei >= 0 && estart == prev_end { prev_end = estart + wb_local_len(e.operand as i64); }
                else { prev_ei = -1; }
                continue;
            }
            if prev_ei >= 0 && estart == prev_end && (op == 0x21 && act <= 1 || op == 0x22 && act == 0) {
                let a = first[events[prev_ei].operand as i64] as i64;
                let b = first[e.operand as i64] as i64;
                if a == b {
                    any_folded = true;
                    if op == 0x21 && act == 0 {
                        action[prev_ei] = 2; action[ei] = 2;
                        prev_ei = -1;
                    } else {
                        action[ei] = 2;
                        prev_end = estart + wb_local_len(e.operand as i64);
                    }
                    continue;
                }
            }
            if op == 0x20 && act == 0 {
                prev_ei = ei; prev_end = estart + wb_local_len(e.operand as i64);
            } else {
                prev_ei = -1;
            }
        }
    }

    var copied = 0;
    if !any_folded && changed && total < 128 {
        // All indexes fit in a single byte and every instruction stays in place.
        for segment in 0..2 {
            var first_event = body_event_count; var limit = events.len; var base = 0;
            if segment != 0 { first_event = 0; limit = body_event_count; base = prelude_bytes; }
            for ei in first_event..limit {
                let event: const WbEvent& = events[ei];
                let op = event.opcode as i64;
                if op < 0x20 || op >= 0x23 { continue; }
                let old = event.operand as i64;
                let mapped = first[old] as i64;
                if old != mapped { bytes[base + (event.start as i64) + 1] = mapped as u8; }
            }
        }
    } else if any_folded || changed {
        // Patch equal-width replacements and append runs around edits that change length.
        for segment in 0..2 {
            var first_event = body_event_count; var limit = events.len; var base = 0;
            if segment != 0 { first_event = 0; limit = body_event_count; base = prelude_bytes; }
            for ei in first_event..limit {
                let event: const WbEvent& = events[ei];
                let op = event.opcode as i64;
                if op < 0x20 { continue; }
                let act = action[ei] as i64;
                if op >= 0x23 && act != 2 { continue; }
                let old = event.operand as i64;
                let start = base + (event.start as i64);
                if act <= 1 {
                    let mapped = first[old] as i64;
                    if old == mapped {
                        if act == 1 { bytes[start] = 0x22; }
                        continue;
                    }
                    var opcode = op;
                    if act == 1 { opcode = 0x22; }
                    let length = wb_local_len(old);
                    if length == wb_local_len(mapped) {
                        if act == 1 { bytes[start] = opcode as u8; }
                        wb_patch_local_index(bytes, start + 1, mapped, length - 1);
                        continue;
                    }
                    wb_copy_body_run(out, bytes, copied, start, fixups, next_fixup);
                    wb_op(out, opcode, mapped);
                    copied = start + length;
                } else {
                    wb_copy_body_run(out, bytes, copied, start, fixups, next_fixup);
                    if act == 3 { wb_byte(out, 0x1a); }
                    copied = start + wb_local_len(old);
                }
            }
        }
    }
    wb_copy_body_run(out, bytes, copied, bytes.len, fixups, next_fixup);
}

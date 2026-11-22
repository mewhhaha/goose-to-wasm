// Deterministic WebAssembly binary encoding. This module has no assembler,
// native compiler, filesystem, or process dependency.

// Share byte and integer writers across Wasm emitters.
inline fn wb_byte(out: u8[>..]&, value: i64) { out.push((value & 255) as u8); }

fn wb_u(out: u8[>..]&, value: i64) {
    if value >= 0 && value < 128 { out.push(value as u8); return; }
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

inline fn wb_op(out: u8[>..]&, opcode: i64, argument: i64) {
    out.push((opcode & 255) as u8);
    if argument >= 0 && argument < 128 { out.push(argument as u8); }
    else { wb_u(out, argument); }
}

inline fn wb_i32(out: u8[>..]&, value: i64) {
    out.push(0x41);
    // Wasm's i32 immediate is signed even when its value is an address.
    let v = (value as! u32) as! i32;
    if v >= -64 && v < 64 { out.push((v & 127) as u8); }
    else { wb_s(out, v); }
}

inline fn wb_i64(out: u8[>..]&, value: i64) {
    out.push(0x42);
    if value >= -64 && value < 64 { out.push((value & 127) as u8); }
    else { wb_s(out, value); }
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
    out.push((opcode & 255) as u8);
    out.push((alignment & 127) as u8);
    if offset >= 0 && offset < 128 { out.push(offset as u8); }
    else { wb_u(out, offset); }
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
    wb_byte(out, 0xfc); wb_u(out, 10); wb_u(out, 0); wb_u(out, 0);
}
fn wb_fill(out: u8[>..]&) { wb_byte(out, 0xfc); wb_u(out, 11); wb_u(out, 0); }
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
struct WbEvent { start: i64, operand: i64, opcode: u8 }
struct WbLocalAccess { start: i32, index: i32 }

// A block, loop or if being read by wb_reuse_locals: where it began (a loop),
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
// Reusable scratch buffers for wb_reuse_locals so per-function emission avoids
// acquiring fresh growable regions on every function body.
struct WbReuseScratch {
    locals_at: WbLocalAccess[>..]&,
    first: i32[>..]&, last: i32[>..]&, written: i32[>..]&, arm: i32[>..]&, stamp: i32[>..]&,
    loop_end: i32[>..]&,
    frames: WbFrame[>..]&, undo: i32[>..]&, covers: i32[>..]&, merged: i32[>..]&,
    head: i32[>..]&, next: i32[>..]&, kinds: i64[>..]&, kept: i64[>..]&, ends: i32[>..]&,
    encoded: u8[>..]&,
    epoch: i32 = 1,
}

fn wb_reuse_locals(locals: i64[>..]&, code: u8[>..]&, params: i64, events: WbEvent[:], body_event_count: i64, prelude_bytes: i64, s: WbReuseScratch&) {
    if locals.len < 2 { return; }
    s.locals_at.clear();
    s.encoded.clear();
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
    if s.merged.len < total { s.merged.resize(total, 0); }
    if s.ends.len < total { s.ends.resize(total, 0); }
    // Ensure loop_end has room for all event positions without shrinking.
    let max_pos = events.len + 2;
    if s.loop_end.len < max_pos { s.loop_end.resize(max_pos, -1); }
    if s.head.len < max_pos { s.head.resize(max_pos, -1); }
    s.frames.clear();
    s.covers.clear();
    let bytes: u8[:] = code;
    let first: i32[:] = s.first[0..total];
    for i in 0..first.len { first[i] = -1; }
    let last: i32[:] = s.last[0..total];
    let written: i32[:] = s.written[0..total];
    let arm: i32[:] = s.arm[0..total];
    let stamp: i32[:] = s.stamp[0..total];
    let undo: i32[:] = s.undo[0..total];
    let merged: i32[:] = s.merged[0..total];
    let ends: i32[:] = s.ends[0..total];
    let loop_end: i32[:] = s.loop_end[0..max_pos];
    var undo_len: i64 = 0;
    var merged_len: i64 = 0;
    var loop_depth: i64 = 0;
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
            let event: const WbEvent& = events[event_index];
            let start = base + event.start;
            let op = event.opcode as i64;
            let index = event.operand;
            position++;
            if op >= 0x20 {
                s.locals_at.push(WbLocalAccess { start: start as i32, index: index as i32 });
                let local = index;
                if first[local] < 0 { first[local] = position; }
                last[local] = position;
                if op == 0x20 {
                    // The outermost loop entered since the write, or of all.
                    var depth = (written[local] as i64) - 1;
                    if depth < 0 { first[local] = 0; depth = 0; }
                    if loop_depth > 0 {
                        while depth < s.frames.len && !s.frames[depth].looping { depth++; }
                        if depth < s.frames.len {
                            let loop_at = s.frames[depth].at;
                            let tag = epoch + loop_at;
                            if stamp[local] != tag {
                                stamp[local] = tag; s.covers.push(local as i32); s.covers.push(loop_at);
                            }
                        }
                    }
                } else if written[local] == 0 {
                    written[local] = (s.frames.len + 1) as i32;
                    undo[undo_len] = local as i32;
                    undo_len++;
                }
            } else if op == 0x0b {
                if s.frames.len == 0 { break; }
                let frame = s.frames.pop();
                let fmark = frame.undo as i64;
                let can_merge = frame.conditional && frame.alternative && !frame.branched;
                let tag = epoch + frame.at;
                merged_len = 0;
                for ui in fmark..undo_len {
                    let local = undo[ui] as i64; written[local] = 0;
                    if can_merge && arm[local] == tag {
                        merged[merged_len] = local as i32;
                        merged_len++;
                    }
                }
                undo_len = fmark;
                let new_depth = (s.frames.len + 1) as i32;
                for mi in 0..merged_len {
                    let local = merged[mi] as i64;
                    if written[local] == 0 {
                        written[local] = new_depth;
                        undo[undo_len] = local as i32;
                        undo_len++;
                    }
                }
                if frame.looping { loop_depth--; loop_end[frame.at as i64] = position; }
            } else if op == 0x02 || op == 0x03 || op == 0x04 {
                if op == 0x03 { loop_depth++; }
                s.frames.push(WbFrame { at: position, looping: op == 0x03, conditional: op == 0x04, undo: undo_len as i32 });
            } else if op == 0x05 {
                // The then arm ends: remember what it wrote, then forget it.
                let depth = s.frames.len - 1; let mark = s.frames[depth].undo as i64;
                let tag = epoch + s.frames[depth].at;
                for ui in mark..undo_len {
                    let loc = undo[ui] as i64;
                    arm[loc] = tag; written[loc] = 0;
                }
                undo_len = mark; s.frames[depth].alternative = true;
            } else if op == 0x0c || op == 0x0d {
                if index < s.frames.len { s.frames[s.frames.len - 1 - index].branched = true; }
            } else if op == 0x0e {
                var cursor = start + 1; let count = wb_read_unsigned(bytes, cursor);
                for target in 0..count + 1 {
                    let label = wb_read_unsigned(bytes, cursor);
                    if label < s.frames.len { s.frames[s.frames.len - 1 - label].branched = true; }
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
    // index of its type that is free again.
    let head_len = (position as i64) + 1;
    let head: i32[:] = s.head[0..head_len];
    for hi in 0..head.len { head[hi] = -1; }
    let next: i32[:] = s.next[0..total];
    var local = total - 1;
    while local >= params {
        let fpos = first[local] as i64;
        if fpos >= 0 { next[local] = head[fpos]; head[fpos] = local as i32; }
        local--;
    }
    // Wasm groups slots by type in first-use order. Link each type's spans
    // in their original order so its first free slot can be found directly.
    s.kinds.clear();
    var begin: i32[8] = [-1; 8]; var tail: i32[8] = [-1; 8];
    for chain in head {
        var member = chain as i64;
        while member >= 0 {
            let following = next[member] as i64; let kind = locals[member - params];
            let slot = (0x7f - kind) & 7;
            if tail[slot] < 0 { s.kinds.push(kind); begin[slot] = member as i32; }
            else { next[tail[slot] as i64] = member as i32; }
            tail[slot] = member as i32; next[member] = -1; member = following;
        }
    }
    s.kept.clear();
    for kind in s.kinds {
        var ends_len: i64 = 0; var skip: i64 = 0; var until: i32 = -1;
        var member = begin[(0x7f - kind) & 7] as i64;
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
            first[member] = (params + s.kept.len + skip) as i32;
            member = next[member] as i64;
        }
        s.kept.resize(s.kept.len + ends_len, kind);
    }
    // Rewrite a one-byte index in place. Copy unchanged runs around wider
    // replacements, including the opcode that precedes each index.
    var copied = 0;
    let accs: const WbLocalAccess[:] = s.locals_at;
    for at in 0..accs.len {
        let start = accs[at].start as i64;
        let old = accs[at].index as i64;
        let index = first[old] as i64;
        if old < 128 && index < 128 {
            bytes[start + 1] = index as u8;
            continue;
        }
        // The emitter uses the shortest unsigned LEB for a local index.
        var end = start + 2;
        if old >= 128 {
            var remaining = old >> 7;
            while remaining > 0 { end++; remaining >>= 7; }
        }
        s.encoded.append(bytes[copied..start + 1]);
        if index < 128 { s.encoded.push(index as u8); } else { wb_u(s.encoded, index); }
        copied = end;
    }
    locals.clear(); locals.append(s.kept);
    if copied == 0 { return; }
    if copied < bytes.len { s.encoded.append(bytes[copied..bytes.len]); }
    code.clear(); code.append(s.encoded);
}

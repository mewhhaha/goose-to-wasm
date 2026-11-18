// Deterministic WebAssembly binary encoding. This module has no assembler,
// native compiler, filesystem, or process dependency.

inline fn wb_byte(out: u8[>..]&, value: i64) { out.push((value & 255) as u8); }

inline fn wb_u(out: u8[>..]&, value: i64) {
    var remaining = value as! u64;
    loop {
        var byte = (remaining & 127) as u8;
        remaining = remaining >> 7;
        if remaining != 0 { byte = byte | 128; }
        out.push(byte);
        if remaining == 0 { return; }
    }
}

inline fn wb_s(out: u8[>..]&, value: i64) {
    var remaining = value;
    loop {
        let byte = remaining & 127;
        remaining = remaining >> 7;
        let done = (remaining == 0 && (byte & 64) == 0) ||
                   (remaining == -1 && (byte & 64) != 0);
        if done { wb_byte(out, byte); return; }
        wb_byte(out, byte | 128);
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
    wb_byte(out, opcode);
    wb_u(out, argument);
}

inline fn wb_i32(out: u8[>..]&, value: i64) {
    wb_byte(out, 0x41);
    // Wasm's i32 immediate is signed even when its value is an address.
    wb_s(out, (value as! u32) as! i32);
}

inline fn wb_i64(out: u8[>..]&, value: i64) { wb_byte(out, 0x42); wb_s(out, value); }

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
    wb_byte(out, opcode);
    wb_u(out, alignment);
    wb_u(out, offset);
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

// A block, loop or if being read by wb_reuse_locals: where it began (a loop),
// where its definite assignments start on the undo stack, and whether a
// branch names it.
struct WbFrame { at: i64, looping: bool = false, conditional: bool = false, alternative: bool = false, branched: bool = false, undo: i64 = 0 }
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
fn wb_reuse_locals(locals: i64[>..]&, code: u8[>..]&, params: i64) {
    if locals.len < 2 { return; }
    var locals_at: i64[>..] = [];
    let bytes: u8[:] = code;
    let total = params + locals.len;
    var first: i64[>..] = []; var last: i64[>..] = []; var written: i64[>..] = []; var arm: i64[>..] = []; var stamp: i64[>..] = [];
    first.resize(total, -1); last.resize(total, -1); written.resize(total, 0); arm.resize(total, -1); stamp.resize(total, -1);
    var loop_end: i64[>..] = [];
    var frames: WbFrame[>..] = []; var undo: i64[>..] = []; var covers: i64[>..] = []; var merged: i64[>..] = [];
    // Only local accesses and control instructions contribute span endpoints.
    // Keep the first position for reads of an implicitly zeroed local.
    var position = -1; var at = 0;
    while at < bytes.len {
        let start = at; let op = bytes[at] as i64; at++;
        var index = -1;
        // Numeric instructions emitted in this range have no immediates.
        if op < 0x45 || op >= 0xfc { index = wb_read_operands(bytes, at, op); }
        let rewrite = op >= 0x20 && op <= 0x22 && index >= params;
        if start != 0 && !rewrite && !(op >= 0x02 && op <= 0x05 || op >= 0x0b && op <= 0x0e) { continue; }
        position++;
        if op == 0x02 || op == 0x03 || op == 0x04 {
            frames.push(WbFrame { at: position, looping: op == 0x03, conditional: op == 0x04, undo: undo.len });
        } else if op == 0x05 {
            // The then arm ends: remember what it wrote, then forget it.
            let depth = frames.len - 1; let mark = frames[depth].undo;
            for index in mark..undo.len { arm[undo[index]] = frames[depth].at; written[undo[index]] = 0; }
            undo.resize(mark); frames[depth].alternative = true;
        } else if op == 0x0b {
            if frames.len == 0 { break; }
            let frame = frames.pop(); merged.clear();
            for index in frame.undo..undo.len {
                let local = undo[index]; written[local] = 0;
                if frame.conditional && frame.alternative && !frame.branched && arm[local] == frame.at { merged.push(local); }
            }
            undo.resize(frame.undo);
            for local in merged { if written[local] == 0 { written[local] = frames.len + 1; undo.push(local); } }
            if frame.looping {
                if frame.at >= loop_end.len { loop_end.resize(frame.at + 1, -1); }
                loop_end[frame.at] = position;
            }
        } else if op == 0x0c || op == 0x0d {
            if index < frames.len { frames[frames.len - 1 - index].branched = true; }
        } else if op == 0x0e {
            var cursor = start + 1; let count = wb_read_unsigned(bytes, cursor);
            for target in 0..count + 1 {
                let label = wb_read_unsigned(bytes, cursor);
                if label < frames.len { frames[frames.len - 1 - label].branched = true; }
            }
        } else if rewrite {
            locals_at.push(start);
            let local = index;
            if first[local] < 0 { first[local] = position; } last[local] = position;
            if op == 0x20 {
                // The outermost loop entered since the write, or of all.
                var depth = written[local] - 1; if depth < 0 { first[local] = 0; depth = 0; }
                while depth < frames.len && !frames[depth].looping { depth++; }
                if depth < frames.len && stamp[local] != frames[depth].at {
                    stamp[local] = frames[depth].at; covers.push(local); covers.push(frames[depth].at);
                }
            } else if written[local] == 0 { written[local] = frames.len + 1; undo.push(local); }
        }
    }
    var pair = 0;
    while pair < covers.len {
        let local = covers[pair]; let start = covers[pair + 1]; pair += 2;
        if start < first[local] { first[local] = start; }
        if loop_end[start] > last[local] { last[local] = loop_end[start]; }
    }
    // Take the locals in the order their spans start; give each the first
    // index of its type that is free again.
    var head: i64[>..] = []; var next: i64[>..] = []; head.resize(position + 1, -1); next.resize(total, -1);
    var local = total - 1;
    while local >= params { if first[local] >= 0 { next[local] = head[first[local]]; head[first[local]] = local; } local--; }
    var slot_type: i64[>..] = []; var slot_free: i64[>..] = []; var slot_of: i64[>..] = []; slot_of.resize(total, -1);
    // A skipped prefix contains only busy slots of this type and slots of
    // other types. It stays skippable until its first same-type span ends.
    var prefix_len: i64[128] = [0; 128];
    var prefix_end: i64[128] = [0; 128];
    for span_start in 0..head.len {
        var member = head[span_start];
        while member >= 0 {
            let kind = locals[member - params];
            var chosen = prefix_len[kind];
            var until = prefix_end[kind];
            if until < span_start { chosen = 0; until = head.len; }
            while chosen < slot_free.len {
                if slot_type[chosen] == kind {
                    let end = slot_free[chosen];
                    if end < span_start { break; }
                    if end < until { until = end; }
                }
                chosen++;
            }
            prefix_len[kind] = chosen;
            prefix_end[kind] = until;
            if chosen == slot_type.len { slot_type.push(kind); slot_free.push(-1); }
            slot_free[chosen] = last[member]; slot_of[member] = chosen; member = next[member];
        }
    }
    // Indexes of one type are adjacent, so the declaration is one group each.
    var kinds: i64[>..] = []; var index_of: i64[>..] = []; index_of.resize(slot_type.len, -1); var kept: i64[>..] = [];
    for kind in slot_type { var known = false; for seen in kinds { if seen == kind { known = true; } } if !known { kinds.push(kind); } }
    for kind in kinds { for candidate, slot in slot_type { if candidate == kind { index_of[slot] = params + kept.len; kept.push(kind); } } }
    // Rewrite a one-byte index in place. Copy unchanged runs around wider
    // replacements, including the opcode that precedes each index.
    var encoded: u8[>..] = []; var copied = 0;
    for start in locals_at {
        var end = start + 1;
        let old = wb_read_unsigned(bytes, end);
        let index = index_of[slot_of[old]];
        if index < 128 && end == start + 2 {
            bytes[start + 1] = index as u8;
            continue;
        }
        wb_raw(encoded, bytes[copied..start + 1]);
        wb_u(encoded, index);
        copied = end;
    }
    locals.clear(); locals.append(kept);
    if copied == 0 { return; }
    if copied < bytes.len { wb_raw(encoded, bytes[copied..bytes.len]); }
    code.clear(); code.append(encoded);
}

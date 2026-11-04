// Deterministic WebAssembly binary encoding. This module has no assembler,
// native compiler, filesystem, or process dependency.

fn wb_byte(out: u8[>..]&, value: i64) { out.push((value & 255) as u8); }

fn wb_u(out: u8[>..]&, value: i64) {
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
    for byte in bytes { out.push(byte); }
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

fn wb_op(out: u8[>..]&, opcode: i64, argument: i64) {
    wb_byte(out, opcode);
    wb_u(out, argument);
}

fn wb_i32(out: u8[>..]&, value: i64) {
    wb_byte(out, 0x41);
    // Wasm's i32 immediate is signed even when its value is an address.
    wb_s(out, (value as! u32) as! i32);
}

fn wb_i64(out: u8[>..]&, value: i64) { wb_byte(out, 0x42); wb_s(out, value); }

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

fn wb_mem(out: u8[>..]&, opcode: i64, alignment: i64, offset: i64) {
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
fn wb_read_unsigned(bytes: u8[:], at: i64&) -> i64 {
    var value: i64 = 0; var shift = 0;
    loop {
        let byte = bytes[at]; at++;
        value |= ((byte as i64) & 127) << shift;
        if (byte & 128) == 0 { return value; } shift += 7;
    }
}
fn wb_skip_leb(bytes: u8[:], at: i64&) {
    loop { let byte = bytes[at]; at++; if (byte & 128) == 0 { return; } }
}
fn wb_instruction(bytes: u8[:], at: i64&) -> WbInstruction {
    let start = at; let opcode = bytes[at] as i64; at++; var index = -1;
    if opcode == 0x02 || opcode == 0x03 || opcode == 0x04 { wb_skip_leb(bytes, at); }
    else if opcode == 0x0c || opcode == 0x0d || opcode == 0x10 || opcode >= 0x20 && opcode <= 0x24 || opcode == 0x3f || opcode == 0x40 { index = wb_read_unsigned(bytes, at); }
    else if opcode == 0x0e { let count = wb_read_unsigned(bytes, at); for i in 0..count + 1 { wb_read_unsigned(bytes, at); } }
    else if opcode == 0x11 { wb_read_unsigned(bytes, at); wb_read_unsigned(bytes, at); }
    else if opcode >= 0x28 && opcode <= 0x3e { wb_read_unsigned(bytes, at); wb_read_unsigned(bytes, at); }
    else if opcode == 0x41 || opcode == 0x42 { wb_skip_leb(bytes, at); }
    else if opcode == 0x43 { at += 4; } else if opcode == 0x44 { at += 8; }
    else if opcode == 0xfc {
        let sub = wb_read_unsigned(bytes, at);
        if sub == 10 { wb_read_unsigned(bytes, at); wb_read_unsigned(bytes, at); }
        else if sub == 11 { wb_read_unsigned(bytes, at); }
    }
    return WbInstruction { start: start, end: at, opcode: opcode, index: index };
}
fn wb_compact_body(out: u8[>..]&, locals: i64[:], code: u8[:], params: i64) {
    var instructions: WbInstruction[>..] = []; var at = 0;
    while at < code.len { let instruction = wb_instruction(code, at); instructions.push(instruction); }
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

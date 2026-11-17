import wasm;
import os;

fn word(data: u8[:], at: i64&) -> i64 {
    var value: u64 = 0;
    for byte in 0..8 { value |= (data[at + byte] as u64) << (byte * 8); }
    at += 8;
    return value as! i64;
}

fn main() {
    let paths = args();
    var data: u8[>..] = [];
    if !read_file(paths[1], data) { return; }
    var result: u8[>..] = [];
    var at = 0;
    var elapsed = 0;
    while at < data.len {
        let params = word(data, at);
        let local_count = word(data, at);
        let size = word(data, at);
        var locals: i64[>..] = [];
        for index in 0..local_count { locals.push(word(data, at)); }
        var code: u8[>..] = [];
        code.append(data[at..at+size]);
        at += size;
        let before = clock_ns();
        wb_reuse_locals(locals, code, params);
        elapsed += clock_ns() - before;
        let sizes: i64[2] = [locals.len, code.len];
        result.append(bytes_of(sizes));
        for kind in locals { result.push(kind as u8); }
        result.append(code);
    }
    if !write_file(paths[2], result) { return; }
    print(elapsed);
}

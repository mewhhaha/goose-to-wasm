fn main() {
    reusable var pool: i64[>..] = [];
    pool.alloc_index(1);
    var payload: u8[3] = [1, 2, 3];
    print(str("x", 17).len);
    print(to_bytes(payload).len);
    var text: u8[>..] = "ab";
    let old = text[..];
    text.format(1234567890);
    print(text.len); print(old[0] as i64); print(old[1] as i64); print(pool.len);
}

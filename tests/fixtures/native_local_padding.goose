struct Packed { tag: u8 = 1, pad 3, word: u16 = 8755 }
recursive fn padded(n: u8) -> i64 {
    let packed = Packed { tag: n };
    let cells = [packed];
    let bytes = bytes_of(cells);
    assert(bytes.len == 6 && bytes[0] == n && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0 && bytes[4] == 51 && bytes[5] == 34);
    return bytes[0] as i64 + bytes[4] as i64 + bytes[5] as i64;
}
fn main() { print(padded(4)); }

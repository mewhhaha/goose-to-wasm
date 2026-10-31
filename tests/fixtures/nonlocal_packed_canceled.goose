struct Cell<T> { tag:u8, value:T }
recursive fn stop8() -> Cell<u16> { return 9 from c8; }
recursive fn c8() -> i64 { return [Cell<u16>{0x11,0x2233},stop8()] from target8; }
recursive fn target8() -> Cell<u16>[u8] { print(c8()); return [Cell<u16>{0x44,0x5566}]; }
recursive fn stop16() -> Cell<u16> { return 9 from c16; }
recursive fn c16() -> i64 { return [Cell<u16>{0x11,0x2233},stop16()] from target16; }
recursive fn target16() -> Cell<u16>[u16] { print(c16()); return [Cell<u16>{0x44,0x5566}]; }
recursive fn stop_rows() -> u16[2] { return 9 from cancel_rows; }
recursive fn cancel_rows() -> i64 { return [[0x1122,0x3344],stop_rows()] from target_rows; }
recursive fn target_rows() -> u16[2][u8] { print(cancel_rows()); return [[0x5566,0x7788]]; }
fn main() {
    let a=target8(); print(a.len," ",a[0].tag as i64," ",a[0].value as i64," ",a[1].tag as i64," ",a[1].value as i64);
    let b=target16(); print(b.len," ",b[0].tag as i64," ",b[0].value as i64," ",b[1].tag as i64," ",b[1].value as i64);
    let rows=target_rows(); print(rows.len," ",rows[0][0] as i64," ",rows[0][1] as i64," ",rows[1][0] as i64," ",rows[1][1] as i64);
}

struct Cell { tag:u8,value:u16 }
recursive fn stop_var() -> u8 { return 9 from canceled_var; }
recursive fn canceled_var() -> i64 { return [stop_var();300000] from target_var; }
recursive fn target_var() -> u8[u32] { print(canceled_var()); return []; }
recursive fn stop_limited() -> u8 { return 9 from canceled_limited; }
recursive fn canceled_limited() -> i64 { return [stop_limited();300000] from target_limited; }
recursive fn target_limited() -> u8[..] { print(canceled_limited()); return []; }
recursive fn stop_packed() -> Cell { return 9 from canceled_packed; }
recursive fn canceled_packed() -> i64 { return [stop_packed();100000] from target_packed; }
recursive fn target_packed() -> Cell[u32] { print(canceled_packed()); return []; }
fn main() {
    let a=target_var(); print(a.len," ",a[200000] as i64);
    let b=target_limited(); print(b.cap," ",b.len," ",b[200000] as i64);
    let c=target_packed(); print(c.len," ",c[70000].tag as i64," ",c[70000].value as i64);
}

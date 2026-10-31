struct V { tag:u8,values:u8[u32] }
struct L { tag:u8,values:u8[..] }
recursive fn stop_v() -> u8 { return 9 from canceled_v; }
recursive fn canceled_v() -> i64 { return V{1,[stop_v();300000]} from target_v; }
recursive fn target_v() -> V { print(canceled_v()); return V{2,[]}; }
recursive fn stop_l() -> u8 { return 9 from canceled_l; }
recursive fn canceled_l() -> i64 { return L{1,[stop_l();300000]} from target_l; }
recursive fn target_l() -> L { print(canceled_l()); return L{2,[]}; }
fn main() {
    let v=target_v(); print(v.tag as i64," ",v.values.len," ",v.values[0] as i64," ",v.values[200000] as i64);
    let l=target_l(); print(l.tag as i64," ",l.values.cap," ",l.values.len," ",l.values[0] as i64," ",l.values[200000] as i64);
}

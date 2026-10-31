struct V { tag:u8,word:u16,values:u8[u8] }
struct L { tag:u8,word:u16,values:u8[..] }
recursive fn stop_v() -> u8 { return 9 from canceled_v; }
recursive fn canceled_v() -> i64 { return V{0x11,0x2233,[stop_v();3]} from target_v; }
recursive fn target_v() -> V { print(canceled_v()); return V{0x44,0x5566,[0x77]}; }
recursive fn stop_l() -> u8 { return 9 from canceled_l; }
recursive fn canceled_l() -> i64 { return L{0x11,0x2233,[stop_l();3]} from target_l; }
recursive fn target_l() -> L { print(canceled_l()); return L{0x44,0x5566,[0x77]}; }
fn main() {
    let v=target_v(); print(v.tag as i64," ",v.word as i64," ",v.values.len," ",v.values[0] as i64," ",v.values[1] as i64," ",v.values[2] as i64);
    let l=target_l(); print(l.tag as i64," ",l.word as i64," ",l.values.cap," ",l.values.len," ",l.values[0] as i64," ",l.values[1] as i64," ",l.values[2] as i64);
}

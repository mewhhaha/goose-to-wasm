struct R { tag:u8,word:u16,values:u8[u8] }
recursive fn stop() -> u16 { return 9 from canceled; }
recursive fn canceled() -> i64 { return R{0x11,stop(),[0x22]} from target; }
recursive fn target() -> R { print(canceled()); var r=R{0x33,0x4455,[0x66]}; return r; }
fn main() { let r=target(); print(r.tag as i64," ",r.word as i64," ",r.values.len," ",r.values[0] as i64); }

struct R { tag:u8,word:u16,values:u8[u8] }
recursive fn stop() -> u16 { return 0x2233 from canceled; }
recursive fn canceled() -> u16 { return R{0xaa,stop(),[]} from target; }
recursive fn target() -> R { return R{0x11,canceled(),[0x22]}; }
fn main() { let r=target(); print(r.tag as i64," ",r.word as i64," ",r.values.len," ",r.values[0] as i64); }

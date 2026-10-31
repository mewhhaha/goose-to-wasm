enum E { Data { tag:u8,word:u16,values:u8[u8] }, Empty }
recursive fn stop() -> u16 { return 9 from canceled; }
recursive fn canceled() -> i64 { return E.Data{0x11,stop(),[0x22]} from target; }
recursive fn target() -> E.Data { print(canceled()); return E.Data{0x33,0x4455,[0x66]}; }
fn main() { let r=target(); print(r.tag as i64," ",r.word as i64," ",r.values.len," ",r.values[0] as i64); }

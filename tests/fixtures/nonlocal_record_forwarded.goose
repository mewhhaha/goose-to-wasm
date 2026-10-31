struct R { tag:u8,word:u16,values:u8[u8] }
recursive fn stop()->u16 { return 9 from canceled; }
recursive fn canceled()->i64 { return R{0x11,stop(),[]},0 from outer; }
recursive fn leave_inner() { return R{0x33,0x4455,[0x66]},7 from inner; }
recursive fn inner()->R,i64 { leave_inner(); return R{0x77,0x8899,[]},8; }
recursive fn outer()->R,i64 { print(canceled()); return inner(); }
fn main() {
    let r,n=outer();
    print(r.tag as i64," ",r.word as i64," ",r.values.len," ",r.values[0] as i64," ",n);
}

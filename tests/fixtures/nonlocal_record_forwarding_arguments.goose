struct R { tag:u8,word:u16,values:u8[u8] }
recursive fn stop()->u16 { return 9 from arg; }
recursive fn arg()->i64 { return R{0x11,stop(),[]},0 from outer; }
recursive fn leave_inner() { return R{0x33,0x4455,[0x66]},7 from inner; }
recursive fn inner(x:i64)->R,i64 { leave_inner(); return R{0x77,0x8899,[]},x; }
recursive fn outer()->R,i64 { return inner(arg()); }
fn main() {
    let r,n=outer();
    print(r.tag as i64," ",r.word as i64," ",r.values.len," ",r.values[0] as i64," ",n);
}

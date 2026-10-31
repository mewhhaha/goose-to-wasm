struct R { tag:u8,word:u16,values:u8[u8] }
recursive fn stop()->u16 { return 9 from canceled; }
recursive fn inner()->R,i64 { return R{0x11,stop(),[]},4; }
recursive fn canceled()->i64 { return inner() from outer; }
recursive fn outer()->R,i64 { print(canceled()); return R{0x33,0x4455,[0x66]},7; }
fn main() {
    let r,n=outer();
    print(r.tag as i64," ",r.word as i64," ",r.values.len," ",r.values[0] as i64," ",n);
}

struct R { tag:u8,word:u16,values:u8[u8] }
recursive fn stop()->u8 { return 9 from canceled; }
recursive fn canceled()->i64 { return R{0x11,0x2233,[0x44]},[stop();3],0 from outer; }
recursive fn leave_inner() { return R{0x55,0x6677,[0x88]},[7,8],7 from inner; }
recursive fn inner()->R,u8[u8],i64 { leave_inner(); return R{0x99,0xaabb,[]},[],8; }
recursive fn outer()->R,u8[u8],i64 { print(canceled()); return inner(); }
fn main() {
    let r,a,n=outer();
    print(r.tag as i64," ",r.word as i64," ",r.values.len," ",r.values[0] as i64," ",
          a.len," ",a[0] as i64," ",a[1] as i64," ",n);
}

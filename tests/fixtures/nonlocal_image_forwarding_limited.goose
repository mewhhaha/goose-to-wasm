recursive fn stop()->u8 { return 9 from canceled; }
recursive fn canceled()->i64 { return [stop();3],0 from outer; }
recursive fn leave_inner() { return [7,8],7 from inner; }
recursive fn inner()->u8[..],i64 { leave_inner(); return [],8; }
recursive fn outer()->u8[..],i64 { print(canceled()); return inner(); }
fn main() {
    let r,n=outer(); print(r.cap," ",r.len," ",r[0] as i64," ",r[1] as i64," ",n);
}

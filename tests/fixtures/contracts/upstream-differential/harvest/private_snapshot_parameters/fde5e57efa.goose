var later_calls:i64=0; var entered:i64=0;
recursive fn receive(xs:u8[..1],n:i64)->i64 { entered=1; return xs.len+n; }
fn later()->i64 { later_calls++; return 7; }
export fn attempt()->i64 { let wide:u8[..2]=[1,2]; return receive(wide[..],later()); }
export fn state()->i64 { later_calls*10+entered }
fn main() {}

var observed:i64=0;
export fn read()->i64 { observed }
export fn peek()->i64 { observed+1 }
recursive fn huge(n:i64)->i64 {
    var bytes:u8[70000]=[0;70000]; bytes[0]=n as u8; bytes[69999]=7;
    return bytes[0] as i64+bytes[69999] as i64;
}
export fn attempt()->i64 { observed=7; return huge(5); }
fn main() {}

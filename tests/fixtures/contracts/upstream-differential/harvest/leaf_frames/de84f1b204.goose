var canary:i64[>..]=[99];
recursive fn copy_increment(var value:i64)->i64 { value++; return value; }
recursive fn cloned(value:i64,divisor:i64)->i64 {
    let after=copy_increment(divisor); return value%divisor+after;
}
fn main() { print(cloned(-17,8)," ",cloned(-17,3)," ",canary[0]); }

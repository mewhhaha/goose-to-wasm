inline fn inner(n:i64)->i64 {
    if n<0 { return -n from inner; } if n==0 { return 3; } return n+2;
}
inline fn outer(n:i64)->i64 {
    if n==7 { return inner(-n); } let value=inner(n);
    if value>5 { return value*2; } return value+1;
}
recursive fn evaluate(n:i64)->i64 { let value=outer(n); return value+1; }
fn main() { print(evaluate(-2)," ",evaluate(0)," ",evaluate(7)," ",evaluate(10)); }

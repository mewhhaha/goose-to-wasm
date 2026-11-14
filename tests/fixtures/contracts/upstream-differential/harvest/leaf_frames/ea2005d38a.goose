recursive fn cycle_a(n:i64)->i64 {
    if n>0 { return cycle_b(n-1); } return 1;
}
recursive fn cycle_b(n:i64)->i64 {
    if n>0 { return cycle_a(n-1); } return bad_owner();
}
recursive fn bad_owner()->i64 { var values:i64[>..]=[7]; return values[0]; }
fn main() { print(cycle_a(2)," ",cycle_b(2)); }

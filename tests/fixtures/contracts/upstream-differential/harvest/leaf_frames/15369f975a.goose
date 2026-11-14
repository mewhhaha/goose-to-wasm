recursive fn referenced(value:i64)->i64 {
    let alias:i64& = value; alias+=2; return alias;
}
recursive fn called(value:i64)->i64 { referenced(value) }
recursive fn produced()->i64[>..] { return [7,8]; }
recursive fn viewed(xs:i64[:])->i64 {
    for &x in xs { x+=1; }
    return xs[0];
}
fn main() {
    var rows:i64[>..]=produced();
    print(referenced(3)," ",called(4)," ",viewed(rows)," ",rows);
}

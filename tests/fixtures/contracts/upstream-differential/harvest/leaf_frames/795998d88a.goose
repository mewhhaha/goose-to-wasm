extern fn root(x:f64)->f64="sqrt";
recursive fn kernel(xs:i64[:],limit:i64)->i64 {
    var sum=0;
    for i in xs.len {
        if i==1 { continue; }
        sum+=xs[i]; if sum>limit { return sum; }
    }
    return sum;
}
recursive fn numeric(x:f64)->f64 { root(x)+1.0 }
fn main() {
    var rows:i64[>..]=[2,3,4,5]; var captured=0;
    recursive fn touch() { captured++; }
    touch(); print(kernel(rows,100)," ",kernel(rows,3)," ",numeric(9.0)," ",captured);
}

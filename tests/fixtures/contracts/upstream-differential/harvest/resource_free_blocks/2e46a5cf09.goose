recursive fn leaf(xs:i64[:])->i64 { return xs[0]+xs[1]; }
export fn run(n:i64)->i64 {
    var kept:i64[>..]=[n,n+1]; var total=0;
    for i in 17 { total+=leaf(kept); }
    var later:i64[>..]=[n+2]; return total+later[0];
}
fn main() {
    print(run(7)," ",run(8)); var checksum=0;
    for i in 1000 { checksum+=run(i%4); } print(checksum);
}

fn exchange(xs:i64[:],i:i64,j:i64) {
    let saved=xs[i]; xs[i]=xs[j]; xs[j]=saved;
}
recursive fn drive(xs:i64[:]) {
    exchange(xs,0,3); exchange(xs,1,2); exchange(xs,0,0);
}
fn main() { var xs=[11,22,33,44]; drive(xs[..]); print(xs); }

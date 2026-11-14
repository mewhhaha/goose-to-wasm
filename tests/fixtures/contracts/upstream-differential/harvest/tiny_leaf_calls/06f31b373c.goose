fn adjust(xs:i64[:],var value:i64) { value+=3; xs[0]=value; }
fn exchange(xs:i64[:],ys:i64[:]) { let saved=xs[0]; xs[0]=ys[0]; ys[0]=saved; }
recursive fn drive() {
    var xs=[11,22,33,44]; var n=5;
    adjust(xs[..],n); exchange(xs[..],xs[1..]); exchange(xs[1..],xs[1..]);
    print(xs," ",n);
}
fn main() { drive(); }

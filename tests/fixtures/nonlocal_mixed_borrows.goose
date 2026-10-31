struct Holder { point: i64& }
var backing: i64[2] = [8, 9];
fn target() -> i64&, i64[>..], const i64[:], Holder {
    recursive fn leave() { return backing[0], [7], backing[..], Holder { backing[0] } from target; }
    leave(); return backing[0], [], backing[..], Holder { backing[0] };
}
fn main() {
    let point, xs, view, holder = target();
    print(point," ",xs," ",view," ",holder.point);
    backing[0] = 10;
    print(point," ",view," ",holder.point);
}

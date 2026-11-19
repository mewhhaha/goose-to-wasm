struct Holder { bytes: i64[:] }
fn head(h: Holder&) -> i64 { return h.bytes[0]; }
fn select(a: Holder&, b: Holder&, second: bool) -> Holder& {
    if second { return b; }
    return a;
}
fn main() {
    var left: i64[2] = [2,3]; var right: i64[2] = [7,9];
    var outside = Holder { bytes: left[..] };
    var count: i64 = 1;
    fn local(h: Holder&) -> i64 { return count + head(h); }
    print(local(outside), " ", head(outside));
    block {
        var inside = Holder { bytes: right[..] };
        print(local(select(outside,inside,true)), " ", head(select(inside,outside,true)));
    };
    outside.bytes = right[..];
    print(local(outside), " ", head(outside));
}

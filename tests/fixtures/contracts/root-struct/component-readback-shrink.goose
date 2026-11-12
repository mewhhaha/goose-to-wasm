// Upstream 32a4f44 test/errors_tc/root_component_readback_shrink.goose:
// rejected: still used
struct Node { link: i64& }
root struct S { first: Node[>..], second: i64[>..] }
struct H { s: S& }
fn use(h: H&, s: S&) {
    let r .= h.s.first[0].link;
    s.second.clear();
    print(r);
}
fn main() {
    var s = S { [], [1] };
    s.first.push(Node { s.second[0] });
    var h = H { s };
    use(h, s);
}

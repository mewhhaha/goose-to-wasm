enum Leaf { Data { values:i64[u16] } }
struct Inner { code:u8, leaf:Leaf.Data }
struct Outer { tag:u8, inner:Inner }
fn main() {
    let box=Outer {1,Inner {2,Leaf.Data {[7,8]}}};
    var grow:i64[>..]=copy(box.inner.leaf.values); grow.push(9);
    print(box.tag," ",box.inner.code," ",grow," ",box.inner.leaf.values.len);
}

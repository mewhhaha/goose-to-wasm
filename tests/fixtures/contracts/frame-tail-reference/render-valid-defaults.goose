struct Stack { n: i64, items: i64[>..<] }
var s = Stack { n: 0, items: [1] };
struct B { n: i64 }
struct Hold { r: i64[>..<]& = s.items }
fn take(r: i64[>..<]& = s.items) { r.push(2); }
fn invoke<F>() { F(); }
fn format(out: u8[>..]&, v: B) {
    take();
    let h = Hold {};
    h.r.push(3);
    invoke() { let r = &s.items; r.push(4); };
    out.append("B");
}
fn main() { print(B { n: 1 }); print(s.items.len); }

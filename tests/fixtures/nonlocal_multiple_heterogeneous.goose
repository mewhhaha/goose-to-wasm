struct Frame { id: i64, values: i32[>..] }
fn target() -> u8[>..], Frame, f64[>..] {
    recursive fn leave() { return [65], Frame { 4, [5] }, [6.5] from target; }
    leave(); return [], Frame { 0, [] }, [];
}
fn main() { var a, b, c = target(); print(a," ",b.id," ",b.values," ",c); a.push(66); b.values.push(6); c.push(7.5); print(a," ",b.values," ",c); }

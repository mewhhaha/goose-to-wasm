var fallback:i64=0;
struct Box { point:i64&, values: i64[] }
fn target() -> i64[>..], Box {
    recursive fn leave() { return [7], Box { fallback, [8] } from target; }
    leave(); return [], Box { fallback, [] };
}
fn main() { let a, b = target(); print(a.len, b.values.len); }
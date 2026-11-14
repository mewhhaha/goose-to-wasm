var fallback:i64=0;
struct Box { point:i64&, values: i64[] }
fn target() -> Box {
    recursive fn leave() { return Box { fallback, [7, 8] } from target; }
    leave(); return Box { fallback, [] };
}
fn main() { print(target()); }
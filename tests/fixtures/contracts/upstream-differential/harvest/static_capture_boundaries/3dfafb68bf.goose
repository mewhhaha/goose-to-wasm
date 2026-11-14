var fallback:i64=0;
struct Element { point:i64&, value:u8 }
fn target() -> Element[u8] {
    recursive fn leave() { return [Element{fallback,7}] from target; }
    leave(); return [];
}
fn main() { let value=target(); print(value.len); }
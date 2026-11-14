
struct Element { data:u8[..2], value:u8 }
fn target() -> Element[u8] {
    recursive fn leave() { return [Element{[1],7}] from target; }
    leave(); return [];
}
fn main() { let value=target(); print(value.len); }
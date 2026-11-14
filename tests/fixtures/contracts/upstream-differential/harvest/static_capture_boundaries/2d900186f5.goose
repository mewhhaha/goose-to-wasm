
struct Element { number:f64, value:u8 }
fn target() -> Element[u8] {
    recursive fn leave() { return [Element{1.5,7}] from target; }
    leave(); return [];
}
fn main() { let value=target(); print(value.len); }
enum E { A, B { n:u8 } }
struct Element { inner:E, value:u8 }
fn target() -> Element[u8] {
    recursive fn leave() { return [Element{E.A,7}] from target; }
    leave(); return [];
}
fn main() { let value=target(); print(value.len); }
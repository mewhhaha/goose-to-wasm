struct Empty {}
struct Element { empty:Empty, value:u8 }
fn target() -> Element[u8] {
    recursive fn leave() { return [Element{Empty{},7}] from target; }
    leave(); return [];
}
fn main() { let value=target(); print(value.len); }
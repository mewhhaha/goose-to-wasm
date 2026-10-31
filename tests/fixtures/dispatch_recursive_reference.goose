enum E { Leaf, Num { value: i64 }, Link { next: E..& } }
recursive fn visit(n: E.Leaf, x: i64) -> i64 { x }
recursive fn visit(n: E.Num, x: i64) -> i64 { x + n.value }
recursive fn visit(n: E.Link&, x: i64) -> i64 { visit(n.next, x) + 1 }
fn main() {
    let leaf: E.. = E.Leaf;
    let num: E.. = E.Num { 3 };
    let a: E.. = E.Link { leaf };
    let b: E.. = E.Link { num };
    print(visit(a, 7), " ", visit(b, 7));
}

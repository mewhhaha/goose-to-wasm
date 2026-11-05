recursive fn visit<T>(value: T, inner: bool) -> i64 {
    fn leave() -> i64 { return 100 from visit; }
    if inner {
        let small: i32 = 7;
        let result = visit(small, false);
        return result + 1;
    }
    return leave();
}
fn main() {
    let large: i64 = 9;
    let small: i32 = 7;
    print(visit(large, true), " ", visit(small, false));
}

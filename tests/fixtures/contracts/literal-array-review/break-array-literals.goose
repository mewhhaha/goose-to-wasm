fn pair<T>(a: T[2], b: T) -> T[2] { [a[1], b] }
fn show(a: u8[2]) { let first: i64 = a[0]; let second: i64 = a[1]; print(first, " ", second); }
fn main() {
    var value: u8 = 9;
    let flag = value > 0;
    show(pair(block { if flag { break [1, 2]; } [3, 4] }, value));
    show(pair(loop { break [5, 6]; }, value));
}

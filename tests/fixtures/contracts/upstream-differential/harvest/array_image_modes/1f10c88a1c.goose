fn capacity()->i64 { return 5; }
fn main() {
    var limited:i64[..]=[..capacity()]; limited.push(7); limited.push(8);
    print(limited.len," ",limited.cap," ",limited);
}

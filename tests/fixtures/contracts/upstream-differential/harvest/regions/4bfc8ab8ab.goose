var neighbor: i64[>..] = [987654321];
recursive fn forward(n: i64) -> i64[>..] {
    if n <= 0 { var local: i64[>..] = [7]; return local; }
    return forward(n - 1);
}
fn main() { let values = forward(100); print(values[0]); }
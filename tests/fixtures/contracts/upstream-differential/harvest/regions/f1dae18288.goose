enum Event { Empty, Data { tag: i64, values: i64[] } }
var neighbor: i64[>..] = [987654321];
fn variant<F>() -> Event.Data { return Event.Data { 1, [F(); 1000000] }; }
fn target(n: i64) -> i64 {
    let event: Event.. = variant() { if n >= 0 { return n + 1; } 4 }; return 0;
}
export fn tick(n: i64) -> i64 { target(n) }
fn main() {}
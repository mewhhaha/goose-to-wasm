enum Event { Empty, Data { id: i64, values: i64[] } }
export fn tick(n: i64) -> i64 {
    let e: Event.. = Event.Data { 1, [if n >= 0 { return n + 1; } else { 2 }; 1000000] };
    return 0;
}
fn main() {}
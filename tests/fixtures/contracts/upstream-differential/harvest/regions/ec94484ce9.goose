enum Event { Data { id: i64 } }
recursive fn make(n: i64) -> Event.. { return Event.Data { n }; }
fn observe(a: const i64&, b: const i64&) -> i64 { return a + b; }
export fn tick(n: i64) -> i64 {
    let value = observe(match make(n) { Data &p => p.id }, match make(n + 1) { Data &p => p.id });
    if value != 2 * n + 1 { abort("bad enum temporary borrow"); } return n + 1;
}
fn main() {}
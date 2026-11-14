enum Event { Data { id: i64 }, Other { id: i64 } }
recursive fn make(n: i64) -> Event.. {
    return Event.Data { if n % 2 > 0 { return Event.Other { n + 10 }; } else { n } };
}
export fn tick(n: i64) -> i64 {
    let e = make(n); let value = match e { Data p => p.id, Other p => p.id - 10 };
    if value != n { abort("bad interrupted enum"); } return n + 1;
}
fn main() {}
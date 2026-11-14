enum Event { Empty, Data { tag: u8, id: i64, values: i64[] }, Other { marker: u8, first: i64, second: i64, third: i64, fourth: i64 } }
var neighbor: i64[>..] = [987654321];
recursive fn make(n: i64) -> Event.. {
    var e: Event.. = Event.Data { 1, 2, [if n == 1 { return Event.Other { 3, 4, 4294967296000000, 0, 0 }; } else if n == 2 { return Event.Data { 5, 6, [7] }; } else if n == 3 { return Event.Empty; } else { 4 }; 1000000] };
    return e;
}
export fn tick(n: i64) -> i64 {
    let a = make(n % 3 + 1); let b = make(2);
    let av = match a { Empty => 0, Data &p => p.values[0], Other &p => p.first };
    let bv = match b { Data &p => p.values[0], _ => -1 };
    let expected = if n % 3 == 0 { 4 } else if n % 3 == 1 { 7 } else { 0 };
    if av != expected || bv != 7 { abort("bad replaced enum tail"); } return n + 1;
}
fn main() {}
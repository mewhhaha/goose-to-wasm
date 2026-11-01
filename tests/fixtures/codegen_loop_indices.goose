extern fn bench_input() -> i64;

fn main() {
    let count = bench_input();
    var indexed_range = 0;
    for value, ordinal in -2..3 {
        if value == 0 { continue; }
        indexed_range += value * 10 + ordinal;
    }
    let values = [2, 3, 5, 7];
    var indexed_array = 0;
    for value, ordinal in values {
        if ordinal == 1 { continue; }
        indexed_array += value * 10 + ordinal;
    }
    var indexed_count = 0;
    for value, ordinal in count { indexed_count += value + ordinal * 2; }
    print(indexed_range, " ", indexed_array, " ", indexed_count);

    var narrow_total = 0;
    var narrow_visits = 0;
    for i: u8 in 0..256 { narrow_total += i; narrow_visits++; }
    print(narrow_total, " ", narrow_visits);

    var captured = 0;
    for i in count {
        fn read() -> i64 { return i; }
        captured += read();
    }
    var exits = 0;
    for i in 2..count + 2 {
        if i == 4 { continue; }
        if i == 7 { break; }
        exits += i;
    }
    print(captured, " ", exits);
}

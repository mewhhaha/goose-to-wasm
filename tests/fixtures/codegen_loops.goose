extern fn bench_input() -> i64;

var calls = 0;
struct State { total: i64 }

fn kernel(state: State&, values: i64[:], lo: i64, hi: i64) -> i64 {
    calls++;
    var sum = 0;
    for i in lo..hi {
        values[i] += i;
        sum += values[i];
    }
    state.total += sum;
    return sum;
}

inline fn explicit(value: i64) -> i64 {
    var sum = 0;
    for i in value { sum += i; }
    return sum;
}

fn tiny(value: i64) -> i64 { return value + 1; }

fn main() {
    let count = bench_input();
    let index = bench_input();
    var values = [10, 20, 30, 40];
    var state = State { 0 };
    var checksum = 0;
    for i in count { checksum += kernel(state, values, 0, 4); }
    print(values, " ", state.total, " ", calls);
    for i in 3 { checksum += tiny(explicit(4)); }
    print(checksum);
    if index >= 0 {
        var seen = 0;
        for i in 1 { seen = kernel(state, values, index, index + 1); }
        print(seen, " ", calls);
    }
}

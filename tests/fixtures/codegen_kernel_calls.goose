extern fn bench_input() -> i64;

var calls = 0;
struct State { total: i64 }

fn kernel(state: State&, values: i64[:], lo: i64, hi: i64) -> i64 {
    calls++;
    var sum = 0;
    for repetition in 2 {
        for i in lo..hi {
            values[i] += (i + 1) * (repetition + 1);
            sum += values[i];
            state.total += values[i] + i;
            state.total ^= i + repetition;
            if values[i] & 1 == 0 { sum += i; }
            else { sum -= repetition; }
        }
    }
    state.total += sum;
    return sum;
}

inline fn explicit(value: i64) -> i64 {
    var sum = 0;
    for i in value {
        for j in 4 {
            sum += i * 3 + j;
            if sum & 1 == 0 { sum += 2; }
            else { sum -= 1; }
            sum ^= i + j;
            sum += (i + 1) * (j + 2);
        }
    }
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

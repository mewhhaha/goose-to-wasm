import std;
extern fn bench_input() -> i64;
struct Large { data: i64[900], marker: i64 }

fn make(n: i64) -> i64[] {
    var values: i64[>..] = [];
    for i in n { values.push(i * 3 + 1); }
    copy(values)
}

fn mutate(values: i64[:]) { for &value in values { value += 10; } }
fn fill_after_push(values: i64[>..]&) -> i64 { values.push(6); 9 }

fn main() {
    let n = bench_input();
    var values: i64[>..] = [];
    let first: i64& = values.push(7);
    for i in 8000 { values.push(i); }
    let middle = values[490..530];
    let ending = values[8001..8001];
    let earlier = values[..1];
    for i in 5000 { values.push(i + 8000); }
    first = 99;
    mutate(middle);
    print(first, " ", earlier[0], " ", values.index_of(first), " ", ending.len,
          " ", values.len, " ", middle[0], " ", middle[39], " ", values[13000]);

    var slices: (i64[:])[>..] = [];
    slices.push(middle);
    slices.push(earlier);
    for i in 600 { slices.push(middle); }
    print(slices[0][0], " ", slices[1][0], " ", slices[601][39]);

    var bytes: u8[>..<] = [];
    bytes.resize(12000, 3);
    fill(bytes[4000..9000], 11);
    var checksum = 0;
    for byte in bytes { checksum += byte; }
    print(checksum, " ", bytes[3999], " ", bytes[4000], " ", bytes[8999], " ", bytes[9000]);
    bytes.resize(5);
    bytes.push(8);
    bytes.append([9, 10]);
    print(bytes, " ", bytes.pop(), " ", bytes.len);
    bytes.pop_n(2);
    bytes.clear();
    print(bytes.len);

    var limited: i64[..8] = [2, 4];
    limited.append([6, 8]);
    limited.resize(6, 10);
    print(limited, " ", limited.cap, " ", limited.pop());
    limited = [20, 30, 40];
    print(limited, " ", limited.cap);
    var runtime: i64[..] = [..n];
    runtime.resize(n, 4);
    runtime = [1, 2];
    print(runtime, " ", runtime.cap);

    let owned = make(n);
    let independent = copy(owned);
    print(owned, " ", independent);

    var large: Large[>..] = [];
    for i in 12 { large.push(Large { [i; 900], i + 100 }); }
    let selected = large[4..8];
    for i in 8 { large.push(Large { [i + 20; 900], i + 200 }); }
    print(selected[0].data[899], " ", selected[3].marker, " ", large[19].data[899]);

    var defaults = default<(i64[..4])[3]>();
    defaults[0].push(17);
    defaults[2].append([20, 30]);
    print(defaults, " ", defaults[1].cap);
    var alias: i64[>..] = [1, 2, 3];
    alias.append(alias[..]);
    print(alias);
    var walked: i64[>..] = [1, 2];
    var walked_sum = 0;
    for value in walked {
        walked_sum += value;
        if walked.len < 5 { walked.push(value + 10); }
    }
    print(walked, " ", walked_sum, " ", walked.index_of(walked[4]));
    var order: i64[>..] = [1];
    order.resize(4, fill_after_push(order));
    print(order);
}

extern fn bench_input() -> i64;
struct Pair { first: i64[..4], second: i64[..4] }
struct Small { values: i64[2] }
enum Choice { No, Yes { number: i64 } }

fn relay(values: i64[..4]) -> i64[..4] { values }
inline fn inline_relay(values: i64[..4]) -> i64[..4] { return values; }

fn main() {
    let selector = bench_input();
    var source: i64[..4] = [1, 2, 3, 4];
    source.resize(1);
    var destination: i64[..4] = [9, 9, 9, 9];
    let retained = destination[..4];
    destination = source;
    print(retained, " ", destination.len);
    destination = copy(source);
    print(retained, " ", destination.len);
    destination = relay(source);
    print(retained, " ", destination.len);
    destination = inline_relay(source);
    print(retained, " ", destination.len);

    let fixed: i64[2] = [5, 6];
    destination = fixed;
    print(retained);
    destination = fixed[..1];
    print(retained);
    let view = fixed[..1];
    destination = view;
    print(retained);
    let smaller: i64[..2] = [7];
    destination = smaller;
    print(retained);
    let fields = Small { [8, 9] };
    destination = fields.values;
    print(retained);
    let nested: (i64[2])[2] = [[10, 11], [12, 13]];
    destination = nested[1];
    print(retained);

    destination = if selector == 0 { fixed[..1] } else { [20] };
    print(retained);
    destination = match selector { 0 => fixed[..1], _ => [21] };
    print(retained);
    destination = block { if selector == 0 { break fixed[..1]; } break [22]; };
    print(retained);
    destination = loop { if selector == 0 { break fixed[..1]; } break [23]; };
    print(retained);
    let choice: Choice = Choice.Yes { selector };
    destination = match choice { No => [24], Yes item => if item.number == 0 { fixed[..1] } else { [25] } };
    print(retained);

    var pair = Pair { [1, 2, 3, 4], [5, 6, 7, 8] };
    let first = pair.first[..4];
    let second = pair.second[..4];
    pair = Pair { [30], [40, 41] };
    print(first, " ", second);
    var pairs: Pair[2] = [Pair { [1, 2, 3, 4], [5, 6, 7, 8] }; 2];
    let nested_ref: i64& = pairs[1].second[2];
    pairs = [Pair { [50], [60] }; 2];
    print(nested_ref);

    var broad: i64[..1600] = [1; 1600];
    let crossing = broad[499..510];
    let ending: i64& = broad[1599];
    broad.clear();
    broad = [70, 71];
    print(crossing, " ", ending);
    broad.resize(1600, 80);
    print(crossing, " ", ending);

    var runtime: i64[..] = [..8];
    runtime.resize(5, 100);
    let runtime_tail = runtime[1..5];
    let incoming: i64[..] = [200];
    runtime = copy(incoming);
    print(runtime_tail, " ", runtime.cap);
    runtime.clear();
    runtime.append(runtime_tail);
    print(runtime, " ", runtime_tail);
}

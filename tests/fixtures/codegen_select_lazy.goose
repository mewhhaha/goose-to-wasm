extern fn bench_input() -> i64;

var calls = 0;
fn observed(x: i64) -> i64 { calls++; return x; }

fn main() {
    let mode = bench_input();
    let choice = bench_input() != 0;
    let x = bench_input();
    let other = bench_input();
    var result = x;
    if mode == 0 {
        if choice { result = observed(x); } else { result = 37; }
    } else if mode == 1 {
        if choice { result = x / other; } else { result = 37; }
    } else if mode == 2 {
        let values = [11, 22];
        if choice { result = values[other]; } else { result = 37; }
    } else if mode == 3 {
        if choice { result = x + 1; } else { result = 37; }
    } else {
        if choice { result = x as i8; } else { result = 37; }
    }
    print(result, " ", calls);
}

extern fn bench_input() -> i64;
struct Pair { left: i64, right: i32 }
fn total(pair: Pair) -> i64 { pair.left + pair.right }
fn main() {
    let seed = bench_input();
    var pair = Pair { seed, 17 };
    pair.left += 3;
    print(total(pair), " ", pair.right);
}

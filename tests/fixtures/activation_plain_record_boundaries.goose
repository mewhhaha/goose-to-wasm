extern fn bench_input() -> i64;
struct Point { x: i64, y: i64 }
recursive fn shift(value: Point, n: i64) -> Point {
    return Point { x: value.x + n, y: value.y - n };
}
recursive fn plain_chain(value: Point, n: i64) -> i64 {
    let moved = shift(value, n);
    return moved.x * 10 + moved.y;
}
recursive fn fixed_sum(values: i64[2]) -> i64 {
    return values[0] * 10 + values[1];
}
recursive fn owned_read(values: i64[>..]) -> i64 { return values.len; }
recursive fn large_local(n: i64) -> i64 {
    let values: i64[1024] = [n; 1024];
    return values[0] + values[1023];
}
recursive fn large_copy(values: i64[1024]) -> i64 {
    let copied = values;
    return copied[1];
}
fn main() {
    let n = bench_input();
    let owned: i64[>..] = [8, 9, 10];
    let large: i64[1024] = [n; 1024];
    print(plain_chain(Point { x: 7, y: 9 }, n), " ", fixed_sum([4, 6]), " ",
          owned_read(copy(owned)), " ", large_local(n), " ", large_copy(large));
}

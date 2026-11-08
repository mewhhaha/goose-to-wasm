extern fn bench_input() -> i64;
recursive fn read() -> i64 { return bench_input(); }
struct Item { value: i64 = read() }
inline fn helper() -> i64 {
    reusable[] var pool: Item[>..] = [];
    let values = pool.alloc_slice(1);
    return values[0].value;
}
recursive fn driver() -> i64 { return helper(); }
fn main() { print(driver()); }

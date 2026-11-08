reusable var pool: i64[>..] = [];
var values: i64[>..] = [5];
fn startup() -> i64 {
    pool.alloc_index(1);
    let kept: i64& = values[0];
    for i in 32 { values.push(i); }
    kept += 6;
    return values.len;
}
var initialized = startup();
fn main() {
    print(initialized); print(values[0]); print(values[32]); print(pool.len);
}

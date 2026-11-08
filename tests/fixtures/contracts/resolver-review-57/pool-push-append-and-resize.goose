fn main() {
    reusable var pool: i64[>..] = [];
    print(pool.alloc_index(99));
    var values: i64[>..] = [7, 9];
    let kept: i64& = values[0];
    let view = values[..];
    for i in 32 { values.push(i); }
    values.append(view);
    kept += 10;
    print(view[0]); print(view[1]); print(values[34]); print(values[35]); print(values.len);
    var resized: i64[>..<] = [1];
    resized.resize(129, 42);
    print(resized[128]); print(resized.len);
}

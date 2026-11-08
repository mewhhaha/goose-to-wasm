fn main() {
    reusable var pool: i64[>..] = [];
    print(pool.alloc_index(99));
    var values: varint[>..] = [];
    let kept: const varint& = values.push(1);
    values.push(-2);
    let view: const varint[:] = values[..];
    for i in 64 { values.push(i); }
    values.append(view);
    print(kept);
    for value in view { print(value); }
    var total: i64 = 0;
    for value in values { total += value as i64; }
    print(total); print(values.len);
}

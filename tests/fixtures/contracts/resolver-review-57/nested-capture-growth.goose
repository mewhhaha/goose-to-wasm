struct Bag { values: i64[>..] }
fn main() {
    reusable var pool: i64[>..] = [];
    pool.alloc_index(1);
    var bag = Bag { values: [13] };
    let kept: i64& = bag.values[0];
    fn grow() { for i in 64 { bag.values.push(i); } }
    grow();
    kept += 4;
    print(bag.values[0]); print(bag.values.len); print(bag.values[64]); print(pool.len);
}

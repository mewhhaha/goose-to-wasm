struct Leaf { value: i64 }
struct Twin { value: i64 }
struct Nested { leaves: Leaf[2], twin: Twin }
var pool: Nested[>..] = [];
struct Handle { first: Leaf&<u32 in pool>, second: Twin&<u32 in pool> }
fn main() {
    pool.push(Nested { leaves: [Leaf { value: 5 }, Leaf { value: 9 }], twin: Twin { value: 14 } });
    let first: Leaf&<u32 in pool> = pool[0].leaves[0];
    let second: Leaf&<u32 in pool> = pool[0].leaves[1];
    let twin: Twin&<u32 in pool> = pool[0].twin;
    let handle = Handle { first: second, second: twin };
    print(first.value, " ", handle.first.value, " ", handle.second.value, " ", pool.len);
}

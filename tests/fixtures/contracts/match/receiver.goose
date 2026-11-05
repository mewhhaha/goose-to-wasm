struct Node { next: Node&<u32 in pool>, value: i64 }
reusable var pool: Node[>..] = [];

fn main() {
    var calls = 0;
    fn choose(value: i64) -> i64 { calls += 1; return value % 3; }
    for i in 0..6 {
        let index = pool.alloc_index(match choose(i) {
            0 => Node { next: self, value: i },
            1 => { Node { next: self, value: i } },
            _ => if i >= 0 { Node { next: self, value: i } } else { Node { next: self, value: -1 } }
        });
        assert(index == i && pool[index].value == i);
        assert(pool.index_of(pool[index].next) == index);
    }
    assert(calls == 6);
    pool.free(2);
    let reused .= pool.alloc_ref(match choose(7) {
        1 => Node { next: self, value: 7 },
        _ => Node { next: self, value: -1 }
    });
    assert(calls == 7 && pool.index_of(reused) == 2 && reused.next.value == 7);
    assert(pool.index_of(reused.next) == 2 && pool.len == 6);
    print("match receiver passed");
}

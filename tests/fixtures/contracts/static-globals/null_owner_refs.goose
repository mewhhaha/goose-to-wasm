let absent: const i64[>..]? = null;
struct Links { first: const i64[>..]?, second: const u8[]? }
let links = Links { null, null };
thread_fn worker(k: i64) {
    assert(absent == null && links.first == null && links.second == null);
    qput(k);
}
fn main() {
    for k in 4 { thread_wait(thread_spawn(worker, k)); assert(qget<i64>() == k); }
    print("null owner refs ok");
}

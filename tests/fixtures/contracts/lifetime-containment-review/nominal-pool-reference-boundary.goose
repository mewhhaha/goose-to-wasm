struct Leaf { value: i64 }
struct Twin { value: i64 }
struct Link { twin: Twin, remote: Leaf& }
var outside = Leaf { value: 17 };
var pool: Link[>..] = [];
var forbidden: Leaf&<u32 in pool>? = null;
fn main() {
    pool.push(Link { twin: Twin { value: 23 }, remote: outside });
    print(pool[0].twin.value);
}

fn main() {
    var bytes = [];
    bytes.append("abc");
    bytes.push('d');
    reusable var pool = [];
    pool.append("ef");
    let i = pool.alloc_index('g');
    print(bytes, " ", pool[i]);
}

// Relative links stay inside one component; recursion borrows an owner
// declared outside it, and a fixed-only owner may live in a recursive frame.
struct Node { value: i64, next: Node&<u32>? }
root struct S { nodes: Node[>..], scratch: i64[>..<] }
recursive fn work(s: S&, n: i64) {
    if n == 0 { return; }
    s.scratch.push(n);
    work(s, n - 1);
    s.scratch.pop();
}
root struct Counter { n: i64 }
recursive fn count(n: i64) -> i64 {
    var s = Counter { n };
    if n == 0 { return s.n; }
    return s.n + count(n - 1);
}
fn main() {
    var s = S { .. };
    let first: Node& = s.nodes.push(Node { 1, null });
    s.nodes.push(Node { 2, first });
    work(s, 5);
    let next = s.nodes[1].next;
    if next { print(next.value, " ", s.scratch.len, " ", count(4)); }
}

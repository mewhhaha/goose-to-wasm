// Each named component is its own pool, including through owner parameters
// and for an owner parameter of a function no call reaches.
struct Node {
    value: i32,
    left: Node&<u32 in state.left>?,
    right: Node&<u16 in state.right>?
}
root struct State<T> { left: T[>..] = [], right: T[>..] = [] }
var state = State<Node> {};

fn connect(s: State<Node>&) {
    s.left[0].left .= s.left[1];
    s.left[0].right .= s.right[0];
}
fn forward(s: State<Node>&) { connect(s); }
fn uncalled(s: State<Node>&) { connect(s); }
fn read(n: Node&) -> i32 {
    let a = n.left;
    let b = n.right;
    if a && b { return a.value + b.value; }
    return 0;
}
struct Seed { value: i32, next: Seed&<u32 in seeds.items> }
root struct Seeds { items: Seed[>..] = [] }
var seeds = Seeds { items: [Seed { value: 9, next: self }] };
fn main() {
    state.left.push(Node { value: 3, .. });
    state.left.push(Node { value: 7, .. });
    state.right.push(Node { value: 11, .. });
    forward(state);
    print(read(state.left[0]), " ", seeds.items[0].next.value);
}

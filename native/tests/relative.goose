struct Node { value: i64, next: Node&<u32>?, me: Node&<u32> }
struct Pair { first: Node, second: Node }
struct PoolNode { value: i64, me: PoolNode&<u16 in pool> }
var pool: PoolNode[>..] = [];
var ticks: i64 = 0;
fn tick() -> i64 { ticks += 1; ticks }
fn node(value: i64, next: Node&?) -> Node { Node { value: value, next: next, me: self } }
fn pair(value: i64) -> Pair { Pair { first: node(value, null), second: node(value + 1, null) } }
fn pooled(value: i64) -> PoolNode { PoolNode { value: value, me: self } }
fn bound(node: PoolNode&<u16 in pool>) -> i64 { node.value }
fn read(node: Node&) -> i64 { node.me.value }
fn main() {
    var nodes: Node[>..] = [];
    nodes.push(node(1, null));
    nodes.push(node(2, nodes[0]));
    nodes[1] = node(3, nodes[0]);
    let next = nodes[1].next;assert(next);if next { assert(next.value == 1); }assert(nodes[1].me.value == 3);
    nodes.append([node(8, nodes[0]), node(9, nodes[1])]);
    assert(nodes[2].me.value == 8 && nodes[3].me.value == 9);
    let appended = nodes[3].next;assert(appended);if appended { assert(appended.value == 3); }
    var links: (Node&<u32>?)[..4] = [];
    links.push(null);links.push(null);assert(links[0] == null && links[1] == null);
    assert(links.pop() == null && links.pop() == null);
    let p = pair(4);assert(read(p.first) == 4 && read(p.second) == 5);
    let fill: Node[3] = [Node { value: tick(), next: null, me: self }; 3];
    assert(ticks == 1);
    for &n in fill { assert(n.value == 1 && n.me.value == 1); }
    let filled_links: (Node&<u32>?)[3] = [null; 3];for r in filled_links { assert(r == null); }
    for i in 3 { pool.push(pooled(i)); }
    for &n in pool { assert(n.me.value == n.value); }
    let selected: PoolNode&<u16 in pool> = pool[2];assert(bound(selected) == 2);
    let addressed = &pool[1].me;assert(addressed.value == 1);
    var relative: PoolNode&<u16 in pool>? = pool[0];relative .= pool[2];
    let decoded .= relative;assert(decoded.value == 2);
    print("native fixed relatives ok");
}

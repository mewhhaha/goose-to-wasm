// An index or bound type may name a field of a global root owner; its
// identity is that component, which bounds analysis matches by field path.
root struct Graph { nodes: i32[>..] = [], edges: (u32 in graph.nodes)[>..] = [], scratch: i32[>..] = [] }
var graph = Graph {};
type NodeId = u32 in graph.nodes;
type EdgeEnd = u16 upto graph.edges;

fn get(i: NodeId) -> i32 { graph.nodes[i] }
fn reset(a: i32[>..]&) { a.clear(); }
fn main() {
    graph.nodes.push(10);
    graph.nodes.push(20);
    graph.edges.push(1 as NodeId);
    graph.edges.push(0 as NodeId);
    let lo = 0 as EdgeEnd;
    let hi = graph.edges.len as EdgeEnd;
    var total = 0;
    for k in lo..hi { total += get(graph.edges[k]); }
    print(total);
    graph.scratch.push(7);
    reset(graph.scratch);
}

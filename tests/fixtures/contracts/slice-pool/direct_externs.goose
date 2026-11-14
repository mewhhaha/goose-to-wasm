// slice_pool_internal's externs called directly on arrays of the program's
// own: a free into empty nodes makes node 0 and a leaf root, and a place
// takes from the free span it recorded.
import slice_pool_internal;

fn main() {
    var nodes: slice_pool_detail::node[>..] = [];
    var tree = slice_pool_detail::tree { .. };
    slice_pool_detail::release_run(nodes, tree, 0, 4);
    print(nodes.len, " ", tree.root, " ", tree.height, " ", nodes[1].n);
    print(slice_pool_detail::place(nodes, tree, 4, 1), " ", slice_pool_detail::place(nodes, tree, 4, 3), " ", nodes[1].n);
    print(slice_pool_detail::place(nodes, tree, 4, 2));
}

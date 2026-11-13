// Elements holding self-relative references are not copied.
struct Node { next: Node&<u32>? }
fn main() { var a: Node[2] = [Node { null }, Node { null }]; a[..1].move_from(a[1..]); }

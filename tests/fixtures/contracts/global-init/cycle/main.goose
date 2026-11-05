import a;
var ROOT: i64 = init_trace::mark(3);
fn main() { assert(cycle_b::B == 1 && cycle_a::A == 2 && ROOT == 3); assert(init_trace::log == 123); print(init_trace::log); }

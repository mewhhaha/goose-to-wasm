import a;
var ROOT: i64 = init_trace::mark(4);
fn main() { assert(chain_c::C == 1 && chain_b::B == 2 && chain_a::A == 3 && ROOT == 4); assert(init_trace::log == 1234); print(init_trace::log); }

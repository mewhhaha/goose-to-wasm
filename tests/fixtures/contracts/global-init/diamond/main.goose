import left;
import common;
import right;
import left;
var ROOT: i64 = init_trace::mark(4);
fn main() { assert(diamond_common::COMMON == 1 && diamond_left::LEFT == 2 && diamond_right::RIGHT == 3 && ROOT == 4); assert(init_trace::log == 1234); print(init_trace::log); }

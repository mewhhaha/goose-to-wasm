import left;
import right;
var FIRST: i64 = init_trace::mark(6);
fn second() -> i64 { assert(FIRST == 6); init_trace::mark(7) }
var SECOND: i64 = second();
fn main() { assert(sibling_left::LEFT == 4 && sibling_right::RIGHT == 5 && SECOND == 7); assert(init_trace::log == 4567); print(init_trace::log); }

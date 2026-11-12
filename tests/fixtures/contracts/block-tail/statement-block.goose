// A block statement whose last statement is a tail `if` (or any tail
// expression) is a statement of its enclosing block, not that block's
// tail: it is checked as void even where the function returns a value.
fn require(ok: bool) -> i64 { if ok { return 0; } return 7; }

fn first_error(a: bool, b: bool) -> i64 {
    if a { { let e = require(b); if e != 0 { return e; } } } { let e = require(a); if e != 0 { return e; } }
    { print("checked") }
    return 0;
}

fn tail_value(x: i64) -> i64 { { x + 1 } }

fn main() { print(first_error(true, false), " ", first_error(false, true), " ", first_error(true, true), " ", tail_value(4)); }

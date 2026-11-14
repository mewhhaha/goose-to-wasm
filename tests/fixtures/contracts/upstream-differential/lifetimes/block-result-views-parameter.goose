// A block's by-value parameter ends with the block, so its result cannot
// view it. Plain upstream accepts this, and its observe() then reads 99,
// which churn() stored where the parameter's elements were.
fn observe(xs: const i64[:], n: i64) -> i64 { xs[0] + n }
fn churn() -> i64 { var fill: i64[>..] = [99, 98]; fill.len - 2 }
fn apply<F>() -> i64 { observe(F([7, 8]), churn()) }
fn main() { print(apply() { xs: i64[>..] => xs[..] }); }

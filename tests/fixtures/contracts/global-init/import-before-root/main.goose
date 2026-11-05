import early;
var LATE: i64 = 42;
fn fetch() -> i64 { LATE }
fn main() { print(early::EARLY); }

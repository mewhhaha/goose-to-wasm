enum Choice { One, Two }
fn choose(c: Choice.One) -> i64 { return 11; }
fn choose(c: Choice.Two) -> i64 { return 22; }
recursive fn route(c: Choice) -> i64 { return choose(c); }
inline fn helper(c: Choice) -> i64 { return route(c) + 3; }
recursive fn driver(c: Choice) -> i64 { return helper(c); }
fn main() { print(driver(Choice.One {}), " ", driver(Choice.Two {})); }

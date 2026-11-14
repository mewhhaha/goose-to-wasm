struct Pair { first:i64, second:i64 }
recursive fn run()->i64 { let pair=Pair { 7,11 }; return pair.first+pair.second; }
fn main() { print(run()); }

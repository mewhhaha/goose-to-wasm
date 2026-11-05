struct Pair { x: i64 } fn make() -> Pair { Pair { x: 5 } } fn main() { var a = Pair { x: 5 }; print(make() .== a); }

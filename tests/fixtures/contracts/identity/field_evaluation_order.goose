struct Pair { x: i64 }
var pair = Pair { x: 5 };
var trace = 0;
fn select(step: i64) -> Pair& { trace = trace * 10 + step; return pair; }
fn main() {
    assert(select(1).x .== select(2).x);
    assert(trace == 12);
    print("field order");
}

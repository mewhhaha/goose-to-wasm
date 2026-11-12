namespace demo;

struct Pair { a: i64, b: i64 }

fn outer(x: i64) -> i64 {
    fn inner(y: demo::Pair) -> i64 { return y.a + y.b; }
    return inner(demo::Pair { x, 1 });
}

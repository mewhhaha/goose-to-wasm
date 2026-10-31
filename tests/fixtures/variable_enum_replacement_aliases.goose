extern fn bench_input() -> i64;
enum Fixed { Empty {}, Data { id: i64 } }
enum Dynamic { Empty, Data { id: i64, values: i64[] } }
var fallback = -1;
fn payloadless() -> Fixed.Empty { return default<Fixed.Empty>(); }
recursive fn fixed_literal(named: bool) -> Fixed.., i64 {
    var e: Fixed.. = Fixed.Data { 100 };
    let kept: const i64& = match e { Data &p => p.id, _ => fallback };
    if named { return e, 0; } return Fixed.Empty {}, kept;
}
recursive fn fixed_call(named: bool) -> Fixed.., i64 {
    var e: Fixed.. = Fixed.Data { 100 };
    let kept: const i64& = match e { Data &p => p.id, _ => fallback };
    if named { return e, 0; } return payloadless(), kept;
}
recursive fn dynamic_literal(named: bool) -> Dynamic.., i64, i64 {
    var e: Dynamic.. = Dynamic.Data { 100, [200, 201] };
    let kept: const i64& = match e { Data &p => p.id, _ => fallback };
    let element: const i64& = match e { Data &p => p.values[0], _ => fallback };
    if named { return e, 0, 0; } return Dynamic.Empty, kept, element;
}
fn main() {
    let n = bench_input();
    let a, first = fixed_literal(n > 0); let b, second = fixed_call(n > 0);
    let e, value, element = dynamic_literal(n > 0);
    print(first, " ", second, " ", value, " ", element);
}

var counter: i64 = 0;
fn next() -> i64 { counter++; counter }
fn first() -> i64[>..], i64, i64 { recursive fn leave() { return [next(), next()], next(), next() from first; } leave(); return [], 0, 0; }
fn middle() -> i64, i64[>..], i64 { recursive fn leave() { return next(), [next(), next()], next() from middle; } leave(); return 0, [], 0; }
fn last() -> i64, i64, i64[>..] { recursive fn leave() { return next(), next(), [next(), next()] from last; } leave(); return 0, 0, []; }
fn main() {
 counter = 0; let xs, a, b = first(); print(xs," ",a," ",b," ",counter);
 counter = 0; let c, ys, d = middle(); print(c," ",ys," ",d," ",counter);
 counter = 0; let e, g, zs = last(); print(e," ",g," ",zs," ",counter);
}

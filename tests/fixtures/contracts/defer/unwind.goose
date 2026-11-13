// Defer bodies on the propagation path of nonlocal returns: calls inside
// expressions with operands pending, inside loops and nested blocks, a
// catching target with its own defers, multiple results, captures.
fn fail(n: i64) -> i64 {
    if n > 2 { return n * 100 from run; }
    return n;
}

fn sum_until(xs: i64[:]) -> i64 {
    var total = 0;
    defer print("sum_until done at ", total);
    for x in xs {
        defer print("iteration ", x);
        {
            defer print("inner ", x);
            total = total + 10 * fail(x) + 1;
        }
    }
    return total;
}

fn run(xs: i64[:]) -> i64 {
    defer print("run done");
    let r = 1000 + sum_until(xs);
    print("not reached when thrown");
    return r;
}

fn pair(n: i64) -> i64, i64 {
    var a = n;
    defer a = -1;
    defer print("pair a ", a);
    return a, n + 1;
}

fn captured() {
    var n = 0;
    fn bump() { n++; }
    defer { bump(); print("captured exit ", n); }
    bump();
    print("captured body ", n);
}

fn each<F>(xs: i64[:]) { for x in xs { F(x); } }

fn search(xs: i64[:], wanted: i64) -> i64 {
    var seen = 0;
    defer print("search seen ", seen);
    each(xs) {
        defer seen++;
        if it == wanted { return seen; }
    }
    return -1;
}

fn main() {
    print(run([1, 2]));
    print(run([1, 2, 3, 4]));
    let a, b = pair(4);
    print(a, " ", b);
    captured();
    print(search([5, 6, 7], 7), " ", search([5], 9));
}

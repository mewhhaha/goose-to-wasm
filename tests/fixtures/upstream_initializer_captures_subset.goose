let G1 = block {
    var n = 1;
    fn bump(k: i64) { n += k; }
    bump(2);
    bump(3);
    n
};
let G3 = block {
    var calls = 0;
    var memo: i64[>..] = [0, 1];
    recursive fn fib(k: i64) -> i64 {
        calls += 1;
        if k < memo.len { return memo[k]; }
        let r = fib(k - 1) + fib(k - 2);
        memo.push(r);
        r
    }
    recursive fn even(k: i64) -> bool {
        calls += 1;
        if k == 0 { true } else { odd(k - 1) }
    }
    fn odd(k: i64) -> bool {
        calls += 1;
        if k == 0 { false } else { even(k - 1) }
    }
    let f = fib(10);
    let e = if even(7) { 1 } else { 0 };
    f * 10000 + e * 1000 + calls
};
let G7 = block {
    var n = 2;
    fn outer(k: i64) -> i64 {
        var m = k;
        fn inner() {
            m *= n;
            n += 1;
        }
        inner();
        inner();
        m
    }
    outer(3) * 100 + outer(1) * 10 + n
};
let G8 = block {
    var a = 1;
    var b = 2;
    fn pick(c: bool) -> i64& {
        if c { return a; }
        b
    }
    let r .= pick(true);
    r += 10;
    let s .= pick(false);
    s += 20;
    a * 100 + b
};
fn main() { print(G1, " ", G3, " ", G7, " ", G8); }

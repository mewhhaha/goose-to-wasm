fn stop() -> i64 { return 9 from canceled; }
recursive fn canceled() -> i64 { return [11], [22, stop()], 4 from target; }
fn target() -> i64[>..], i64[>..], i64 {
    var left: i64[>..] = [1, 2]; var right: i64[>..] = [10, 20];
    print(canceled()); return left, right, 5;
}
fn main() { var a, b, n = target(); print(a," ",b," ",n); a.push(7); b.push(70); print(a," ",a.pop()," ",b," ",b.pop()); }

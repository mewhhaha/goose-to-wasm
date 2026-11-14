// An exported function is a root of the lifetime analysis even when no main
// calls it: a host does (upstream checks export bodies as roots).
export "probe" fn probe() -> i64 {
    var a: i64[>..] = [1, 2, 3];
    let r: i64& = a[0];
    a.clear();
    a.push(9);
    return r;
}

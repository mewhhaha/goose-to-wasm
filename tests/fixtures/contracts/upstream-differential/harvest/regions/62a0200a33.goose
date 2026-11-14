export fn tick(n: i64) -> i64 {
    var step = 0;
    let result: i64[>..] = loop {
        var local: i64[>..] = [n];
        if step == 0 { step++; continue; }
        break match n % 2 {
            0 => block { var nested: i64[>..] = [n + 1]; break copy(nested); },
            _ => { local.push(n + 1); copy(local) }
        };
    };
    return result[result.len - 1];
}
fn main() {}
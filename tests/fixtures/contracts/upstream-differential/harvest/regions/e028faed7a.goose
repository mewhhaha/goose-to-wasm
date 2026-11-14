fn local(n: i64) -> i64 {
    var values: i64[>..] = [1]; let alias: i64[>..]& = values;
    alias = [if n >= 0 { return 7; } else { 1 }; 4294967296]; return 0;
}
fn parameter(values: i64[>..], n: i64) -> i64 {
    let alias: i64[>..]& = values;
    alias = [if n >= 0 { return 7; } else { 1 }; 4294967296]; return 0;
}
fn named(n: i64) -> i64[>..] {
    var values: i64[>..] = [1];
    values = [if n >= 0 { return [7]; } else { 1 }; 4294967296]; return values;
}
export fn tick(n: i64) -> i64 {
    let a = local(n); let b = parameter([1], n);
    for i in 2 {
        var dying: i64[>..] = [1];
        dying = [if n >= 0 { continue; } else { 1 }; 4294967296];
    }
    let result = named(n);
    if a != 7 || b != 7 { abort("wrong interrupted result"); } return n + result[0] - 6;
}
fn main() {}
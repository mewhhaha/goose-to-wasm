// Owned results, dynamic storage, and a reference that survives array growth.
enum Report { Empty, Values { data: i64[], label: u8[] } }

fn collect(count: i64) -> Report.. {
    if count == 0 { return Report.Empty; }
    var values: i64[>..] = [];
    for i in count { values.push(i * i); }
    Report.Values { copy(values), str("count=", count) }
}

fn main() {
    let result = collect(6);
    let independent = copy(result);
    print(independent);

    var stable: i64[>..] = [];
    let first: i64& = stable.push(7);
    for i in 2000 { stable.push(i); }
    first = 42;
    print("first=", first, ", length=", stable.len);
}

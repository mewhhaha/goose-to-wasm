fn main() { var a: i64[3] = [1,2,3]; print(a.index_of(if a.len > 1 { &a[1] } else { &a[0] })); }

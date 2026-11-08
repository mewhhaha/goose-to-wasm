fn main() { var a: i64[2] = [4, 5]; var x: i64 = 7; a[0] = x; x += a[1]; a[1] += x; print(a[0]); print(a[1]); print(x); }

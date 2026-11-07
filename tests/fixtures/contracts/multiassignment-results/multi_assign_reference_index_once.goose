var index = 0;
fn next() -> i64 { let old = index; index += 1; old }
fn pair() -> i64, i64 { return 3, 4; }
fn main() { var a = 0; var b = 0; var refs: (i64&)[2] = [a, b]; refs[next()], refs[next()] = pair(); print(a, " ", b, " ", index); }

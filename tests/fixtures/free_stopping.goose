fn index() -> i64 { print("index"); exit(0); } fn main(){ reusable var pool:i64[>..]=[1]; pool.free(index()); print("unreachable"); }

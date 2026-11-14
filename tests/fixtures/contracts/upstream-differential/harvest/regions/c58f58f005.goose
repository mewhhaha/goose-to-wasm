fn bench_input() -> i64 { return 5; }
enum E {Done}
var values:i64[>..]=[1];
var neighbor:i64[>..]=[987654321];
fn target()->E.. {
    recursive fn replace() {
        values=[if bench_input()>0 {return E.Done from target;} else {7};1000000];
    }
    replace();return E.Done;
}
fn main() {let e=target();}
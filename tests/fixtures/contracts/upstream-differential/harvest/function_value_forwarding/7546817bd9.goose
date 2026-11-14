
struct Pair { first:i64, second:i64 }
fn invoke<F>(a:Pair,b:Pair)->bool { F(a,b) }
fn forward<F>(a:Pair,b:Pair)->bool { invoke(a,b) { x,y => F(x,y) } }
fn run()->bool {
    let left=Pair { 1, 10 }; let right=Pair { 2, 20 };
    forward(left,right) { x,y =>
        fn nested()->bool { x.first<y.first }
        nested()
    }
}
fn main() { print(run()); }


struct Pair { first:i64, second:i64 }
fn invoke<F>(a:Pair,b:Pair)->bool { F(a,b) }
fn forward1<F>(a:Pair,b:Pair)->bool { invoke(a,b) { x,y => F(y,x) } }
fn forward2<F>(a:Pair,b:Pair)->bool { forward1(a,b) { x,y => F(y,x) } }
var state=Pair { 1, 10 };
fn first()->Pair { return state; }
fn later()->Pair { state.first=99; return state; }
fn run()->i64 {
    var saw_first=0; var calls=0;
    for i in 3 {
        forward2(first(),later()) { a,b =>
            calls++;
            if a.first==1 && b.first==99 { saw_first=1; }
            if i==2 { return saw_first*10+calls; }
            false
        };
    }
    return saw_first*10+calls;
}
fn main() { print(run()); }

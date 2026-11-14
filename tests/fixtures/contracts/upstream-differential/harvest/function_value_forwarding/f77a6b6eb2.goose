
enum Event { Empty, Data { value:i64 } }
fn invoke<F>(a:Event..,b:Event..)->bool { F(a,b) }
fn forward<F>(a:Event..,b:Event..)->bool { invoke(copy(a),copy(b)) { x,y => F(x,y) } }
fn below(a:Event..,b:Event..)->bool {
    match a { Data &left => match b { Data &right => left.value<right.value, Empty => false }, Empty => false }
}
fn run()->bool {
    let a:Event..=Event.Data { 1 }; let b:Event..=Event.Data { 2 };
    forward(copy(a),copy(b)) { x,y => below(copy(x),copy(y)) }
}
fn main() { print(run()); }

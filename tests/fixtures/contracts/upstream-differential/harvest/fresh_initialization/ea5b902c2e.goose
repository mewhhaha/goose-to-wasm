
struct Ref { point:i64&, value:i64 }
export fn run() {
    var value:i64=7; let holder=Ref { value,3 };
    value=19; print(holder.point," ",holder.value);
}
fn main() { run(); }

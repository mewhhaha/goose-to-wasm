// An optional reference converts to no value: only a reference parameter
// takes it.
struct W { n: i64 }
fn emit<T>(value: T?, w: W&) { print("optional"); }
fn emit(value: i64, w: W&) { print("int"); }
fn main() {
    var w = W { 0 };
    var x = 5; let r: i64? = x;
    emit(r, w);
    r.emit(w);
}

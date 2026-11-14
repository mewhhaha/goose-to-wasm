var shared:i64[>..]=[2,3];
var shrinking:i64[>..<]=[7,8,9];
fn bump(xs:i64[:]) { for i in xs.len { xs[i]+=1; } }
fn escaped()->i64[>..] {
    var local:i64[>..]=[10,11];
    recursive fn leave() { return copy(local) from escaped; }
    leave(); return [];
}
fn main() {
    bump(shared[..]); shrinking.pop();
    let result=escaped(); var captured:i64[>..]=[20,21];
    recursive fn append() { captured.push(22); }
    append(); print(shared," ",shrinking," ",result," ",captured);
}

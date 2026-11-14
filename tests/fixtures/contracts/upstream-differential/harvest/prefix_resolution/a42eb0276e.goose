recursive fn leave() { return [1] from enable; }
fn enable()->i64[>..] { leave(); return []; }
var values:i64[>..]=[9];
fn create<F>()->i64[] { return [F(),F()+1,F()+2]; }
fn install() {
    values=create() { print(7); 7 };
}
fn main() {
    print(enable().len);
    install();
    print(values.len," ",values[0]," ",values[1]," ",values[2]);
    let kept:const i64& =values.push(17);
    values.push(23);
    print(kept," ",values.len," ",values[4]);
}

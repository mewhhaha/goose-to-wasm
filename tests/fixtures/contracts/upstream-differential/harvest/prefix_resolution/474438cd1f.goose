recursive fn leave() { return [1] from enable; }
fn enable()->i64[>..] { leave(); return []; }
struct Inner { id:i64, values:i64[>..] }
struct Outer { tag:u8, inner:Inner }
recursive fn make(n:i64)->Outer {
    recursive fn observe()->i64 { return n+1; }
    return Outer { 7, Inner { n, [observe()] } };
}
fn main() {
    let packet=make(10);
    let kept:const i64& =packet.inner.id;
    recursive fn read_kept()->i64 { return kept; }
    for i in 16 {
        let temporary=make(i);
        if temporary.inner.id!=i || temporary.inner.values[0]!=i+1 { abort("bad temporary"); }
    }
    let duplicate=copy(packet);
    duplicate.inner.id+=100;
    duplicate.inner.values[0]+=200;
    print(read_kept()," ",packet.inner.id," ",packet.inner.values[0]," ",duplicate.inner.id," ",duplicate.inner.values[0]," ",packet.tag);
    print(enable().len);
}

enum E { A{a:u8,values:u8[u8]}, B{b:u16,values:u8[u16]}, Empty }
recursive fn replace(b:bool)->E..,i64,i64,i64 {
    var e:E..=E.A{0x11,[0x22]};
    let kept:const E.A& =match e { A &p=>p, _=>abort("bad") };
    if b { return E.B{0x3344,[0x55]},kept.a as i64,kept.values.len,kept.values[0] as i64; }
    return e,0,0,0;
}
fn main() {
    let e,a,n,x=replace(true); print(a," ",n," ",x);
    match e { B p=>print(p.b as i64," ",p.values.len," ",p.values[0] as i64), _=>{} }
}

enum E { A{id:u8,values:u16[u8]}, B{id:u8,values:u16[..]}, Empty }
var neighbor:i64[>..] = [987654321];
recursive fn leave(depth:i64,value:i64) {
    if depth>0 {leave(depth-1,value);return;}
    return E.A{7,[value as u16]},E.B{8,[(value+1) as u16]},17 from target;
}
recursive fn target(depth:i64,value:i64)->E..,E..,i64 {
    if depth>0 {return target(depth-1,value);}
    leave(3,value);return E.Empty,E.Empty,0;
}
export fn tick(n:i64)->i64 {
    var left,right,k=target(12,n);
    let value=match left {A &p=>{if p.id!=7 || p.values.len!=1 {abort("bad enum left");} p.values[0] as i64},_=>-1};
    if value!=n || k!=17 {abort("bad enum tuple");}
    return match right {B &p=>{if p.id!=8 || p.values.cap!=1 || p.values.len!=1 {abort("bad enum right");} p.values.pop();p.values.push((n+1) as u16);p.values[0] as i64},_=>-1};
}
fn main() {}
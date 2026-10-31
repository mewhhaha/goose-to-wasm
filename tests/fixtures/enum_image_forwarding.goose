enum E { Empty, Data{tag:u8,values:u16[u8]} }
recursive fn pair(n:i64)->E.Data,E.Data,i64 {
    if n>0 { return pair(n-1); }
    return E.Data{7,[300,400]},E.Data{8,[500]},17;
}
recursive fn wrapped(n:i64)->E..,E..,i64 { return pair(n); }
fn main() {
    let a,b,n=wrapped(12);
    match a { Data p=>print(p.tag as i64," ",p.values.len," ",p.values[0] as i64," ",p.values[1] as i64), _=>{} }
    match b { Data p=>print(p.tag as i64," ",p.values.len," ",p.values[0] as i64," ",n), _=>{} }
}

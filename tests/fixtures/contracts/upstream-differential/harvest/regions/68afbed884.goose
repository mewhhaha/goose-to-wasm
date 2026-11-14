enum E {Data{values:u8[u32]},Other{marker:u8},Empty}
var neighbor:i64[>..] = [987654321];
recursive fn leave(n:i64) {
    if n%2>0 {return E.Other{9} from target;}
    return E.Data{[8]} from target;
}
recursive fn target(n:i64)->E.. {
    var own:E..=E.Data{[if n>=0 {leave(n);0} else {7};1000000]};
    return own;
}
export fn tick(n:i64)->i64 {
    let e=target(n);
    let value=match e {Data &p=>p.values[0] as i64,Other p=>p.marker as i64,Empty=>0};
    if value!=(if n%2>0 {9} else {8}) {abort("bad replaced enum");}
    return n+1;
}
fn main() {}
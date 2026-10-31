struct R{tag:u8,word:u16,values:varint[varint]} recursive fn sum(xs:const varint[:])->i64{var s=0;for x in xs{s+=x;}return s;}
var empty:R;var global=R{0x11,0x2233,[64,-65,8192]};
fn main(){let a=R{2,3,[64;128]};let b=copy(a);print(empty.values.len," ",global.word as i64," ",sum(global.values));print(a.values.len," ",b.values.len," ",sum(b.values));}
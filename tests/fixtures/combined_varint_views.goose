recursive fn sum(xs:const varint[:])->i64{var total=0;for x in xs{total+=x;}return total;}
recursive fn first(xs:const varint[:])->const varint& {for x in xs{return x;}abort("empty");}
fn main(){
 let a:varint[varint]=[64,-65,8192,-8193];let b:varint[varint]=copy(a);
 let v:const varint[:]=a[..];let w:const varint[:]=v[..];
 print(a," ",b," ",sum(w)," ",first(w)," ",first(w) .== first(a));
 for x,i in a {print(i as i64," ",x);}
 for &x,i in b {print(i," ",x);}
}

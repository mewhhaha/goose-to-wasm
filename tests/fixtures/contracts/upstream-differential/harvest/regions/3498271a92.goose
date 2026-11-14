var neighbor:i64[>..]=[987654321];
recursive fn make(n:i64)->varint[u16]{return[n-5000,-n,8192];}
recursive fn first(xs:const varint[:])->const varint&{for x in xs{return x;}abort("empty");}
export fn tick(n:i64)->i64{
let rows=make(n);let kept:const varint& =first(rows);
for i in 10{if make(i).len!=3{abort("bad varint temporary");}}
var total=0;for x in rows{total+=x;}
if kept!=n-5000 || total!=3192{abort("bad encoded reference");}
return n+1;
}
fn main(){}
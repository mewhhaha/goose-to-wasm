struct R{value:varint,after:u16}
var r=R{64,0x2233};var saved:const varint& =r.value;
export fn value()->i64{r.value}
export fn kept()->i64{saved}
export fn after()->i64{r.after}
export fn clone()->i64{let c=copy(r);return c.value+c.after as i64;}
fn main(){}
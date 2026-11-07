fn bump(x:i64&){x+=1;}fn choose(c:bool,a:i64&,b:i64&){bump(block{if c{break a;}break b;});}
fn main(){var a=1;var b=2;bump(block{break a;});choose(true,a,b);choose(false,a,b);print(a," ",b);}

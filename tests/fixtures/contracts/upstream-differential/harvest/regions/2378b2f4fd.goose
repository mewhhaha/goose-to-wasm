var neighbor:i64[>..]=[987654321];var a:varint[>..]=[];
recursive fn values<F>()->varint[u8]{return[1,F(),8192];}
fn apply<F>(){a.append(F());}
fn target(n:i64)->i64{a.append(values(){if n>=0{return n+1;}else{-65}});return 0;}
export fn tick(n:i64)->i64{a.clear();a.push(64);let r=target(n);
let kept:const varint& =a.push(9);var total=0;for x in a{total+=x;}
if r!=n+1 || a.len!=2 || total!=65 || kept!=9{abort("bad canceled append");}return r;}
fn main(){}
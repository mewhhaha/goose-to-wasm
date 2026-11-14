var neighbor:i64[>..]=[987654321];
recursive fn values(n:i64)->varint[>..]{if n==0{return[64,-65];}return values(n-1);}
export fn tick(n:i64)->i64{var a:varint[>..]=[n];a.append(values(20));var total=0;for x in a{total+=x;}return total+2;}
fn main(){}
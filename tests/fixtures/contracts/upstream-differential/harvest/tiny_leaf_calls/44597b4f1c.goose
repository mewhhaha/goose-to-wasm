var backing:i64[4]=[17,34,51,68]; var saved:i64[:];
fn write(xs:i64[:],i:i64,j:i64,value:i64) { xs[i]=value; xs[j]=value+1; }
recursive fn drive(i:i64,j:i64,value:i64) { write(saved,i,j,value); }
export fn tick(i:i64,j:i64,value:i64) { drive(i,j,value); }
fn main() { saved=backing[..]; tick(0,1,7); print(backing); backing=[17,34,51,68]; }

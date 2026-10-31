var calls:i64=0;
fn next()->u64 {calls+=1;return 99;}
recursive fn make()->u64[..0] {return [];}
fn accept(value:u64[..0])->i64 {return value.len+value.cap;}
fn main() {
    var a:u64[..0]=[next();0];let b=make();let wide:u64[..1]=a;
    let narrow:u64[..0]=wide[..];
    a.append([]);a.resize(0);a.pop_n(0);a.clear();
    print(a.len," ",b.len," ",wide.len," ",narrow.len," ",accept(a)," ",calls);
}

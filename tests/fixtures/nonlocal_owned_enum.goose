recursive fn leave(n:i64) { if n>0 {leave(n-1);return;} return [9] from effect; }
fn effect()->i64[>..] {leave(1);return [];}
enum E{Empty,Data{values:i64[]}}
fn main(){print(effect());let e:E..=E.Data{[4,5]};match e{Data &v=>print(v.values),Empty=>{}}}

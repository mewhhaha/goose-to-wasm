inline fn adjust(n:i64)->i64 { if n==0 { return 1; } return n+1; }
inline fn owner(n:i64)->i64[>..] { return [n]; }
recursive fn produce(n:i64)->i64[>..] { return [n,n+1]; }
recursive fn take(value:i64&)->i64 { value+=1; return value; }
fn owner_result(n:i64)->i64 { let values=owner(n); return values[0]; }
fn allocation_arg(n:i64)->i64 { adjust(produce(n)[0]) }
fn addressed_arg(var n:i64)->i64 { adjust(take(n)) }
recursive fn default_value()->i64 { var values:i64[>..]=[9]; return values[0]; }
struct Defaulted { value:i64=default_value() }
inline fn defaults(n:i64)->i64 { let item=default<Defaulted>(); return item.value+n; }
fn default_arg(n:i64)->i64 { adjust(defaults(n)) }
inline fn escape_inner(n:i64)->i64 { if n<0 { return 7 from escape_outer; } return n+2; }
inline fn escape_outer(n:i64)->i64 { return escape_inner(n)+1; }
fn escape(n:i64)->i64 { escape_outer(n) }
fn captured_input(n:i64)->i64 {
    let extra=n+3; inline fn add(value:i64)->i64 { return extra+value; } return add(n);
}
recursive fn driver() {
    print(owner_result(2)," ",allocation_arg(4)," ",addressed_arg(5)," ",default_arg(1)," ",
          escape(-1)," ",escape(2)," ",captured_input(4));
}
fn main() { driver(); }

var order=0; var left_calls=0; var right_calls=0;
fn left(value:i64)->i64 {
    order=order*10+1; left_calls++;
    print("left ",order," ",left_calls," ",right_calls); return value;
}
fn right(value:i64)->i64 {
    order=order*10+2; right_calls++;
    print("right ",order," ",left_calls," ",right_calls); return value;
}
recursive fn calculate(a:i64,b:i64)->i64 { left(a)%right(b) }
fn main() { print("before"); print(calculate((0x8000000000000000 as! i64),0)); }

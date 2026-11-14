var calls=0;
recursive fn condition(value:i64)->bool { calls++; return value>0; }
recursive fn pick(value:i64)->i64 { if condition(value) { 123 } else { 456 } }
recursive fn observe(value:i64)->i64 { calls++; return value; }
recursive fn effect(flag:bool)->i64 { if flag { observe(11) } else { observe(22) } }
fn main() {
    print(pick(1)," ",calls," ",pick(0)," ",calls); calls=0;
    print(effect(true)," ",calls," ",effect(false)," ",calls);
}
recursive fn signed(flag:bool)->i8 { if flag { -128 } else { -1 } }
fn main() { print(signed(true)," ",signed(false)); }
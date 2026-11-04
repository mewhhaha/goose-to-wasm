var out:u8[>..]=[];
fn argument()->i64 {out.append("side");return 7;}
fn main(){out.format("a",argument(),"b");print(out);}

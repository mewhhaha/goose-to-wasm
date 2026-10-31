fn invoke<F>(b:bool) { if b { F(); } }
recursive fn target(b:bool) -> i64,u8[u64],u8[u64] {
    var left:u8[>..] = [1,2]; var right:u8[>..] = [4,5];
    invoke(b) { return (left.push(3) as i64)+(right.push(6) as i64),[7],[8]; }
    return 0,left,right;
}
fn main() { let n,a,b=target(true); print(n," ",a.len," ",b.len); }

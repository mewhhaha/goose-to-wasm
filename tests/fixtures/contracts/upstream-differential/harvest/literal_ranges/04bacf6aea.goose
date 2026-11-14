var saved:u8[:]; var backing:u8[4]=[17,34,51,68];
var observed:i64[2]=[0,0];
export fn tick(seed:i64)->i64 {
    let xs=saved; let state=observed[..];
    for index in -1..2 {
        let value=xs[index+1]; state[0]+=value; state[1]++;
    }
    return state[0];
}
export fn total()->i64 { return observed[0]; }
export fn visited()->i64 { return observed[1]; }
fn main() { saved=backing[..]; }

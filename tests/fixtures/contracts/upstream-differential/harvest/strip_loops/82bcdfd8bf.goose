var saved:u8[:];
var backing:u8[4]=[17,34,51,68];
var total_seen:i64=0; var visited_count:i64=0;
recursive fn observe(value:i64)->i64 { return value; }
export fn tick(seed:i64)->i64 {
    let xs=saved;
    for value,i in xs { let term=(value as i64)+i+(i%3); total_seen+=term; visited_count++; }
    return total_seen;
}
export fn total()->i64 { return total_seen; }
export fn visited()->i64 { return visited_count; }
fn main() { saved=backing[..]; }

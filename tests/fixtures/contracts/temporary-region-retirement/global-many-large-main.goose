fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
let scalar0 = make(0).len;
let scalar1 = make(1).len;
let scalar2 = make(2).len;
let scalar3 = make(3).len;
let scalar4 = make(4).len;
let scalar5 = make(5).len;
let scalar6 = make(6).len;
let scalar7 = make(7).len;
let scalar8 = make(8).len;
let scalar9 = make(9).len;
let scalar10 = make(10).len;
let scalar11 = make(11).len;
let scalar12 = make(12).len;
let scalar13 = make(13).len;
let scalar14 = make(14).len;
let scalar15 = make(15).len;
let scalar16 = make(16).len;
let scalar17 = make(17).len;
let scalar18 = make(18).len;
let scalar19 = make(19).len;
let scalar20 = make(20).len;
let scalar21 = make(21).len;
let scalar22 = make(22).len;
let scalar23 = make(23).len;
let scalar24 = make(24).len;
let scalar25 = make(25).len;
let scalar26 = make(26).len;
let scalar27 = make(27).len;
let scalar28 = make(28).len;
let scalar29 = make(29).len;
let scalar30 = make(30).len;
let scalar31 = make(31).len;
fn chunk() -> i64[] { [1; 1024] }
fn main() { var total: i64 = 0; for i in 0..1000 { for value in chunk() { total += value; } } print(scalar0 + scalar1 + scalar2 + scalar3 + scalar4 + scalar5 + scalar6 + scalar7 + scalar8 + scalar9 + scalar10 + scalar11 + scalar12 + scalar13 + scalar14 + scalar15 + scalar16 + scalar17 + scalar18 + scalar19 + scalar20 + scalar21 + scalar22 + scalar23 + scalar24 + scalar25 + scalar26 + scalar27 + scalar28 + scalar29 + scalar30 + scalar31, " ", total); }

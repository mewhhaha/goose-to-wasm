var effects: i64 = 0;
fn condition(x: i64) -> bool { effects += 1; return x == 0; }
fn scalar(x: i64) -> i64 { if condition(x) { return 10; } else { return 20; } }
fn assigned(x: i64) -> i64 { var v = 0; v = if condition(x) { return 30; } else { return 40; }; v }
fn tupled(x: i64) -> i64, i64 { if condition(x) { return 1, 2; } else { return 3, 4; } }
fn matched(x: i64) -> i64 { match x { 0 => { return 50; }, _ => { return 60; }, } }
fn match_tuple(x: i64) -> i64, i64 { match x { 0 => { return 5, 6; }, _ => { return 7, 8; }, } }
fn one_live(x: i64) -> i64 { let v = if condition(x) { return 70; } else { 80 }; return v + 1; }
fn match_live(x: i64) -> i64 { let v = match x { 0 => { return 90; }, _ => 100 }; return v + 1; }
fn owner(x: i64) -> i64[>..] { if condition(x) { return [11, 12]; } else { return [13, 14]; } }
fn empty(x: i64) { if condition(x) {} else {} match x { 0 => {}, _ => {}, } }
fn main() {
    print(scalar(0), " ", scalar(1));
    print(assigned(0), " ", assigned(1));
    let a, b = tupled(0); let c, d = tupled(1); print(a, " ", b, " ", c, " ", d);
    print(matched(0), " ", matched(1));
    let e, f = match_tuple(0); let g, h = match_tuple(1); print(e, " ", f, " ", g, " ", h);
    print(one_live(0), " ", one_live(1), " ", match_live(0), " ", match_live(1));
    let first = owner(0); let second = owner(1); print(first[0], " ", first[1], " ", second[0], " ", second[1]); empty(0); empty(1); print(effects);
}

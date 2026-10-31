struct Limited { tag:u8,word:u16,values:u8[..] }
struct Var { tag:u8,word:u16,values:u8[u8] }
fn step(x:i64) -> i64 { print(x); return x; }
fn build_limited<F>() -> Limited { return Limited{tag:step(1) as u8,word:F(),values:[..step(3)]}; }
fn run_limited(b:bool) -> i64 {
    let r=build_limited(){ if b {return 7;} else {step(2) as u16} }; return r.values.cap;
}
fn build_var<F>() -> Var { return Var{tag:step(1) as u8,word:F(),values:[step(3) as u8]}; }
fn run_var(b:bool) -> i64 {
    let r=build_var(){ if b {return 7;} else {step(2) as u16} };
    return r.tag as i64+r.word as i64+r.values[0] as i64;
}
fn main() { print(run_limited(false)); print(run_limited(true)); print(run_var(false)); print(run_var(true)); }

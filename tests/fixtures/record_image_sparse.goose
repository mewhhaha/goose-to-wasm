struct R { tag:u8,values:u8[u32] }
enum E { Data { tag:u8,values:u8[u32] }, Other }
recursive fn stop() -> u8 { return 9 from canceled; }
recursive fn canceled() -> i64 { return [stop();300000] from target; }
recursive fn target() -> u8[u32] { print(canceled()); return []; }
fn make_record() -> R { return R{1,target()}; }
fn make_enum() -> E.. { return E.Data{7,target()}; }
fn main() {
    let r=make_record(); print(r.tag as i64," ",r.values.len," ",r.values[200000] as i64);
    let e=make_enum();
    match e { Data &p => { print(p.tag as i64," ",p.values.len," ",p.values[200000] as i64); }, _ => abort("wrong tag") };
}

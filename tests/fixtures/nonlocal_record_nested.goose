struct Inner { word:u16,values:u8[u8] }
struct R { tag:u8,inner:Inner }
recursive fn stop() -> u16 { return 9 from canceled; }
recursive fn canceled() -> i64 { return R{0x11,Inner{stop(),[0x22]}} from target; }
recursive fn target() -> R { print(canceled()); return R{0x33,Inner{0x4455,[0x66]}}; }
fn main() {
    let r=target(); let kept:const Inner& = r.inner;
    print(r.tag as i64," ",kept.word as i64," ",kept.values.len," ",kept.values[0] as i64);
}

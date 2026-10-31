extern fn bench_input() -> i64;

recursive fn fixed_copy(named: bool) -> u8[u8] {
    let original: u8[u8] = [1,2];
    if named { return original; }
    let other: u8[2] = [7,8];
    return copy(other);
}

recursive fn pair() -> u16[u8], i64 { return [7,8],9; }
recursive fn raw_pair() -> u16[>..], i64 { return pair(); }
recursive fn wide_pair() -> u16[u16], i64 { return pair(); }

recursive fn limited_alias(named: bool) -> u16[..], u16 {
    var local: u16[..] = [1,2];
    let kept: u16& = local[0];
    if named { return local,0; }
    return [7,8],kept;
}

fn main() {
    let named = bench_input() != 0;
    let fixed = fixed_copy(named);
    print(fixed.len," ",fixed[0] as i64," ",fixed[1] as i64);
    var raw, marker = raw_pair();
    print(raw.len," ",marker);
    for i in 254 { raw.push(10); }
    print(raw.len);
    let wide, wide_marker = wide_pair();
    print(wide.len," ",wide[0] as i64," ",wide[1] as i64," ",wide_marker);
    let limited, old = limited_alias(named);
    print(limited.len," ",limited.cap," ",limited[0] as i64," ",old as i64);
}

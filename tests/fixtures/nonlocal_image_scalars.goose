recursive fn leave_bool() { return [true,false] from target_bool; }
recursive fn target_bool() -> bool[u8] { leave_bool(); return []; }
recursive fn leave_f32() { return [1.5,-2.25] from target_f32; }
recursive fn target_f32() -> f32[u64] { leave_f32(); return []; }
recursive fn leave_f64() { return [3.5,-4.25] from target_f64; }
recursive fn target_f64() -> f64[..] { leave_f64(); return []; }
recursive fn leave_signed() { return [-7,8] from target_signed; }
recursive fn target_signed() -> i64[] { leave_signed(); return []; }
fn main() {
    let flags=target_bool(); print(flags.len," ",flags[0]," ",flags[1]);
    let small=target_f32(); print(small.len," ",small[0]," ",small[1]);
    var wide=target_f64(); print(wide.cap," ",wide.len," ",wide[0]," ",wide[1]);
    print(wide.pop()); wide.push(5.5); print(wide[1]);
    let signed_values=target_signed(); print(signed_values.len," ",signed_values[0]," ",signed_values[1]);
}

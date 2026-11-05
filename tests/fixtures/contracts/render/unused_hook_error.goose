struct Unused { value: i64 }
fn format(out: u8[>..]&, value: Unused) { format(out, value.missing); }
fn format(out: u8[>..]&, value: const i64[:]) { out.append("readonly"); }
fn main() {
    var values: i64[>..] = [1];
    let readonly: const i64[:] = values[..];
    print(readonly);
}

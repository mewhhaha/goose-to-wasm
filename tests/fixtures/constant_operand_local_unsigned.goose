// A local's initializer does not turn its unsigned value into a literal.
fn main() {
    let local: u32 = 1;
    print(-local);
}

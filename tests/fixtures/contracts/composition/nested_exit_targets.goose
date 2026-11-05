struct Holder { view: u8[:] }
fn read(holder: Holder&) -> u8[:] { let view = holder.view; return view; }
fn outer(holder: Holder&, leave_outer: bool) -> i64 {
    let result: i64;
    fn inner() {
        fn route() {
            let view = read(holder);
            assert(view == "ab");
            if leave_outer { result = 10; return result from outer; }
            return from inner;
        }
        route();
    }
    inner();
    result = 20;
    return result;
}
fn main() {
    var text: u8[>..] = [97, 98];
    var holder = Holder { view: text[..] };
    print(outer(holder, true), " ", outer(holder, false));
}

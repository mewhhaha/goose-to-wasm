// UFCS with an explicit list: x.f<T>(a) is f<T>(x, a). A field compared with
// `<` stays a comparison. (After upstream test/typing/explicit_type_args.goose.)
fn size<T>() -> i64 {
    let one: T[1] = [default<T>()];
    bytes_of(one).len
}
fn wrap<T>(n: i64) -> i64 { size<T>() * n }
struct Holder { n: i64 }
fn scaled<T>(h: Holder, by: i64) -> i64 { size<T>() * h.n * by }

fn main() {
    let h = Holder { 3 };
    print(h.scaled<u16>(5), " ", h.n.wrap<f64>(), " ", h.n.wrap<u8>().wrap<u16>());
    let m = 4;
    print(h.n < m, " ", h.n < m || m > h.n, " ", h.n < size<u8>(), " ", h.n < m == true);
}

struct Empty {}
struct Num { n: i64 }
enum Plain { A, B { pad }, C { pad 0 }, D { pad 3 } }
enum Hooked { A, B { pad }, C { pad 0 }, D { pad 3 }, E { n: Num } }
fn format(out: u8[>..]&, value: Num) { format(out, "#", value.n); }
fn main() {
    print(Plain.A, "|", Plain.B {}, "|", Plain.C {}, "|", Plain.D {}, "|", Empty {});
    print(Hooked.A, "|", Hooked.B {}, "|", Hooked.C {}, "|", Hooked.D {}, "|", Hooked.E { Num { 9 } });
    var plain: Plain..[] = [Plain.A, Plain.B {}, Plain.C {}, Plain.D {}];
    var hooked: Hooked..[] = [Hooked.A, Hooked.B {}, Hooked.C {}, Hooked.D {}, Hooked.E { Num { 7 } }];
    print(plain);
    print(hooked);
}

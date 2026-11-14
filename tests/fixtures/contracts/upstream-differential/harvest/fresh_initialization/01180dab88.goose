
struct Pair { first:i64, second:i64 }
recursive fn seed()->Pair { Pair { 1,2 } }
recursive fn run() {
    var pair=seed();
    pair=Pair { pair.second,pair.first };
    print(pair.first," ",pair.second);
    fn observe()->i64 { pair.first }
    pair=Pair { 9,observe() };
    print(pair.first," ",pair.second);
}
fn main() { run(); }

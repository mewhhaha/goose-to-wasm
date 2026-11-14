struct Pair { first:i64, second:i64 }
fn main() {
    let bonus=9;
    recursive fn captured(p:Pair)->i64 { p.first+bonus }
    print(captured(Pair { 1,2 }));
}

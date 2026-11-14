
struct Pair { first:i64, second:i64 }
var calls:i64=0;
recursive fn step(n:i64)->i64 { calls=calls*10+n; return calls; }
recursive fn run() {
    let values:i64[3]=[step(1);3];
    let pair=Pair { step(2),step(3) };
    print(values[0]," ",values[2]," ",pair.first," ",pair.second," ",calls);
    let empty:i64[0]=[step(4);0]; print(empty.len," ",calls);
}
fn main() { run(); }

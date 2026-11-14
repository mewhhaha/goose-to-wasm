
var calls:i64=0;
recursive fn next()->i64 { calls++; return calls; }
struct Item { first:i64=next(), second:i64=next() }
recursive fn run() {
    let items=default<Item[2]>();
    print(items[0].first," ",items[0].second," ",items[1].first," ",items[1].second," ",calls);
}
fn main() { run(); }

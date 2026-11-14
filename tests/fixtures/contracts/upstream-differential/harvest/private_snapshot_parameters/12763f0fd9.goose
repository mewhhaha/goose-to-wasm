enum Choice { A { value:i64 }, B { value:i64 } }
recursive fn score(c:Choice.A)->i64 { c.value+1 }
recursive fn score(c:Choice.B)->i64 { c.value+2 }
recursive fn selected(c:Choice)->i64 { score(c) }
fn main() {
    let c:Choice=Choice.B { 7 };
    print(selected(c)," ",score(Choice.A { 3 }));
}

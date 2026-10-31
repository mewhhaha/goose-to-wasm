struct Pair { x: i64, y: i64 }
struct Borrowed { item: i64&, view: i64[:] }
var pairs: Pair[2] = [Pair { 1, 2 }, Pair { 10, 20 }];
var route: Pair& = pairs[0];
var calls = 0;
fn index() -> i64 { calls++; return 0; }
fn replacement() -> Pair { route .= pairs[1]; return Pair { 30, 40 }; }
fn bump(p: Pair) -> Pair { var result = p; result.x += 5; return result; }
fn main() {
    route = replacement();
    print(pairs[0].x, " ", pairs[0].y, " ", route.x);
    pairs[index()] = bump(pairs[0]);
    pairs[index()].y++;
    pairs[0] = pairs[0];
    print(pairs[0].x, " ", pairs[0].y, " ", calls);
    var p = Pair { 7, 8 }; p = bump(p); print(p.x, " ", p.y);
    var value = 11; var data: i64[2] = [12, 13];
    let borrowed = Borrowed { value, data[..] };
    let copied = copy(borrowed);
    value = 21; data[0] = 22;
    print(copied.item, " ", copied.view[0], " ", copied.view[1]);
    let q = block { break pairs[0]; };
    pairs[0] = Pair { 100, 200 };
    print(q.x, " ", q.y);
}

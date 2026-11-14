// A default fixed array builds every element from the declared field
// defaults, so an effectful default runs once per element, in order: at the
// top, nested, in a struct field, from `..`, in a global and as the source
// of a growable array. A written fill `[v; n]` evaluates `v` once. A slot's
// temporaries (an owned array a default builds and drops) are released before
// the next slot's, across more slots than there are data regions.
var calls: i64 = 0;
recursive fn next() -> i64 { calls++; return calls; }
struct Item { first: i64 = next(), second: i64 = next() }
struct Outer { tag: i64 = 9, items: Item[3] }
struct Node { id: i64 = next(), link: Node&? = null }
fn pair(n: i64) -> i64[>..] { return [n, n + 1]; }
fn sum(values: const i64[:]) -> i64 { var total = 0; for value in values { total += value; } return total; }
struct Owned { value: i64 = sum(pair(next())) }
struct Linked { value: i64 = sum(pair(next())), link: Linked&? = null }
var global = default<Item[2]>();

fn main() {
    print(global[0].first, " ", global[1].second, " ", calls);
    calls = 0;
    let items = default<Item[2]>();
    print(items[0].first, " ", items[0].second, " ", items[1].first, " ", items[1].second, " ", calls);
    let grid = default<Item[2][2]>();
    print(grid[0][0].first, " ", grid[0][1].first, " ", grid[1][0].first, " ", grid[1][1].second, " ", calls);
    let outer = default<Outer>();
    print(outer.tag, " ", outer.items[0].first, " ", outer.items[2].second, " ", calls);
    let partial = Outer { tag: 1, .. };
    print(partial.items[0].first, " ", partial.items[2].second, " ", calls);
    let once = [default<Item>(); 3];
    print(once[0].first, " ", once[2].first, " ", once[2].second, " ", calls);
    var grown: Item[>..] = default<Item[2]>();
    grown.append(default<Item[2]>());
    print(grown[0].first, " ", grown[1].second, " ", grown[3].second, " ", calls);
    var again = default<Item[2]>();
    again = default<Item[2]>();
    print(again[0].first, " ", again[1].second, " ", calls);
    let nodes = default<Node[3]>();
    print(nodes[0].id, " ", nodes[1].id, " ", nodes[2].id, " ", calls);
    let owned = default<Owned[300]>();
    print(owned[0].value, " ", owned[299].value, " ", calls);
    var owned_grown: Owned[>..] = default<Owned[300]>();
    print(owned_grown[0].value, " ", owned_grown[299].value, " ", calls);
    let linked = default<Linked[300]>();
    print(linked[0].value, " ", linked[299].value, " ", calls);
    var linked_grown: Linked[>..] = [];
    linked_grown.append(default<Linked[300]>());
    print(linked_grown[0].value, " ", linked_grown[299].value, " ", calls);
}

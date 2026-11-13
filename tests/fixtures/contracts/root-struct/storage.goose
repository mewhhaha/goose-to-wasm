// Root owners in native storage: a local and a global owner whose components
// grow and shrink independently, passed by reference through nested and
// recursive calls, held in fields and arrays, while references into one
// component stay valid as another changes. Owners in a loop body reuse
// their storage across iterations and exits.
root struct Pool {
    items: i64[>..] = [],
    free: i64[>..<] = [],
    log: u8[>..] = [],
    allocations: i64 = 0
}
struct View { pool: Pool&, tag: i64 }

var shared = Pool { log: "g:" };

fn alloc(pool: Pool&, value: i64) -> i64 {
    pool.allocations += 1;
    pool.log.push('a');
    if pool.free.len > 0 {
        let slot = pool.free.pop();
        pool.items[slot] = value;
        return slot;
    }
    pool.items.push(value);
    return pool.items.len - 1;
}
fn release(pool: Pool&, slot: i64) { pool.free.push(slot); pool.log.push('r'); }
fn fill(pool: Pool&, count: i64, base: i64) { for i in 0..count { pool.alloc(base + i); } }
recursive fn churn(pool: Pool&, depth: i64) -> i64 {
    if depth == 0 { return pool.items.len; }
    let slot = alloc(pool, depth * 100);
    let inner = churn(pool, depth - 1);
    pool.release(slot);
    return inner;
}
fn total(pool: const Pool&) -> i64 { var sum = 0; for x in pool.items { sum += x; } return sum; }
fn describe(view: View) { print(view.tag, ":", view.pool.items.len, ":", view.pool.allocations); }
fn busiest(a: Pool&, b: Pool&) -> Pool& { if a.allocations >= b.allocations { a } else { b } }
fn scratch(rounds: i64) -> i64 {
    var best = 0;
    for r in 0..rounds {
        var local = Pool { .. };
        fill(local, r + 1, r);
        if r == 2 { continue; }
        if total(local) > 20 { break; }
        best = total(local);
    }
    return best;
}

fn main() {
    var pool = Pool { .. };
    fill(pool, 3, 1);
    let kept .= pool.items[1];
    release(pool, 0);
    release(pool, 2);
    print(alloc(pool, 70), " ", kept, " ", pool.free.len);
    pool.free.clear();
    print(churn(pool, 3), " ", pool.items.len, " ", pool.free.len, " ", total(pool));
    pool.free.resize(1);
    print(pool.allocations, " ", pool.log, " ", pool.free);
    fill(shared, 2, 40);
    let first .= shared.items[0];
    release(shared, 1);
    print(alloc(shared, 9), " ", first, " ", shared.items, " ", shared.log);
    var views: View[2] = [View { pool, 1 }, View { shared, 2 }];
    for view in views { describe(view); }
    let most = busiest(pool, shared);
    most.log.append("!");
    print(pool.log.len, " ", shared.log.len, " ", scratch(10), " ", kept);
}

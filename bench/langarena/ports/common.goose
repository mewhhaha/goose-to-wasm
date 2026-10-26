// LangArena harness/RNG adaptation. Original MIT notice is in LICENSE.
// All hosts implement these scalar imports; inputs remain runtime values.
extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
extern fn bench_barrier(value: i64) -> i64;
extern fn bench_sink(value: i64);

let IM = 139968;
let IA = 3877;
let IC = 29573;
let INIT = 42;

var rng_last: i32 = 42;

fn reset() { rng_last = INIT; }

fn next_int(max: i64) -> i32 {
    rng_last = (rng_last * IA + IC) % IM;
    return (rng_last / IM as f64 * max) as! i32;
}

fn checksum_str(v: u8[:]) -> u32 {
    var hash: u32 = 5381;
    for b in v { hash = (hash << 5) + hash + b; }
    return hash;
}

// The checksum is computed/consumed after the end timestamp, as in bench.goose.
// A revision edit has an observable exit status without changing the protocol.
fn finish(checksum: u32, elapsed: i64, revision: i64) {
    bench_sink(checksum);
    print(checksum);
    print(elapsed);
    if revision != 0 { exit(revision); }
}

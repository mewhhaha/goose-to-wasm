// The upstream sieve.goose is copied unchanged beside this entrypoint.
import sieve;
extern fn bench_input() -> i64;
fn main() {
    let limit = bench_input(); let iterations = bench_input();
    var state = sieve::Sieve { limit: limit, checksum: 0 };
    for i in iterations { sieve::run(state, i); }
    print(sieve::checksum(state));
}

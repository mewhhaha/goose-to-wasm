// Adapted from upstream Goose samples/07_sieve.goose at revision
// 2e2bedef5b980bf013cac5aaa0095bfea64e5569. Kept the sieve and deterministic
// summary; reduced N to 100,000 to fit the direct target data region and
// removed host clock/stderr calls.
//
// The sieve of Eratosthenes uses one byte flag per candidate.
// Each composite is crossed out by stepping through its multiples.
//
// Build and run (from the repository root):
//   python scripts/goose_wasm.py build examples/sieve.goose --backend direct -o build/sieve.wasm
//
import std;

let N = 100000;

fn main() {
    // One byte per candidate, all "prime" until crossed out, filled in place.
    var flags: u8[>..] = [];
    flags.resize(N + 1, 1);
    flags[0] = 0;
    flags[1] = 0;
    var i = 2;
    while i * i <= N {
        if flags[i] == 1 {
            // Cross out the multiples from i*i on: smaller ones were hit
            // by a smaller prime already.
            var j = i * i;
            while j <= N { flags[j] = 0; j += i; }
        }
        i++;
    }

    // Collect the primes. `%` is Euclidean, so bucketing by residue needs
    // no care about signs; here it counts the primes by their last digit.
    var primes: i32[>..] = [];
    var by_last_digit: i64[10] = [0; 10];
    for n, k in flags {
        if n == 1 {
            primes.push(k as i32);
            by_last_digit[k % 10] += 1;
        }
    }
    // Twin primes: pairs two apart.
    var twins = 0;
    for k in 1..primes.len {
        if primes[k] - primes[k - 1] == 2 { twins++; }
    }
    print(primes.len, " primes up to ", N);
    print("last ten: ", primes[^10..]);
    print("twin pairs: ", twins);
    print("by last digit: ", by_last_digit);
    // A checksum in wrapping unsigned arithmetic, which is what unsigned
    // types mean: no overflow checks, no surprises.
    var h: u32 = 0;
    for p in primes { h = h * 31 + p as u32; }
    print("hash ", h);
}

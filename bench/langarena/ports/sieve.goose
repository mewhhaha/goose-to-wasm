// From LangArena goose/src/sieve.goose; MIT, see LICENSE/README.md.
import std;
import math;
import common;

let ARENA_REVISION = 0;

// Bounded global backing storage replaces the per-run growable allocation.
// The active prefix is initialized on EVERY run, inside the timed loop.
var primes: u8[3000001] = [0; 3000001];

struct Sieve { limit: i64, checksum: u32 }

fn run(s: Sieve&, iteration_id: i64) {
    let limit = s.limit;

    fill(primes[..limit + 1], 1);
    primes[0] = 0;
    primes[1] = 0;

    let sqrt_limit = sqrt(limit as f64) as i64;

    for p in 2..sqrt_limit + 1 {
        if primes[p] == 1 {
            var multiple = p * p;
            while multiple <= limit {
                primes[multiple] = 0;
                multiple += p;
            }
        }
    }

    var last_prime = 2;
    var count = 1;

    var n = 3;
    while n <= limit {
        if primes[n] == 1 {
            last_prime = n;
            count++;
        }
        n += 2;
    }

    s.checksum += (last_prime + count) as! u32;
}

fn main() {
    let limit = bench_input();
    let iterations = bench_input();
    let warmups = bench_input();
    assert(limit >= 2 && limit <= 3000000 && iterations > 0 && warmups >= 0);
    reset();
    var s = Sieve { limit: limit, checksum: 0 };
    reset();
    for i in warmups { run(s, i); }
    reset();
    let count = bench_barrier(iterations);
    let started = bench_clock();
    for i in count { run(s, i); }
    let elapsed = bench_clock() - started;
    finish(s.checksum, elapsed, ARENA_REVISION);
}

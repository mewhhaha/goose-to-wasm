// From LangArena goose/src/fannkuchredux.goose; MIT, see LICENSE/README.md.
import std;
import common;

let ARENA_REVISION = 0;

fn fannkuchredux(n: i32) -> i32, i32 {
    var perm1: i32[32] = [0; 32];
    for i in 32 { perm1[i] = i as i32; }

    var perm: i32[32] = [0; 32];
    var count: i32[32] = [0; 32];
    var max_flips_count: i32 = 0;
    var perm_count = 0;
    var checksum: i32 = 0;
    var r: i64 = n;

    loop {
        while r > 1 {
            count[r - 1] = r as i32;
            r--;
        }

        copy_into(perm[..n], perm1[..n]);

        var flips_count: i32 = 0;
        var k = perm[0];

        while k != 0 {
            let k2 = (k + 1) >> 1;
            for i in k2 {
                let j = k - i;
                swap(perm[i], perm[j]);
            }
            flips_count++;
            k = perm[0];
        }

        if flips_count > max_flips_count {
            max_flips_count = flips_count;
        }

        if perm_count % 2 == 0 {
            checksum += flips_count;
        } else {
            checksum -= flips_count;
        }

        loop {
            if r == n { return checksum, max_flips_count; }

            let perm0 = perm1[0];
            for i in r {
                let j = i + 1;
                swap(perm1[i], perm1[j]);
            }

            perm1[r] = perm0;
            count[r] -= 1;
            if count[r] > 0 { break; }
            r++;
        }

        perm_count++;
    }
}

struct Fannkuchredux { n: i64, result_val: u32 }

fn run(s: Fannkuchredux&, iteration_id: i64) {
    let checksum, max_flips = fannkuchredux(s.n as i32);
    s.result_val += (checksum as! u32) * 100 + (max_flips as! u32);
}

fn main() {
    let n = bench_input();
    let iterations = bench_input();
    let warmups = bench_input();
    assert(n >= 1 && n <= 32 && iterations > 0 && warmups >= 0);
    reset();
    var s = Fannkuchredux { n: n, result_val: 0 };
    reset();
    for i in warmups { run(s, i); }
    reset();
    let count = bench_barrier(iterations);
    let started = bench_clock();
    for i in count { run(s, i); }
    let elapsed = bench_clock() - started;
    finish(s.result_val, elapsed, ARENA_REVISION);
}

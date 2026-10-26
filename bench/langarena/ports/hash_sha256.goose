// From LangArena goose/src/buffer_hash.goose; MIT, see LICENSE/README.md.
// This is LangArena's custom eight-lane digest, NOT cryptographic SHA-256.
import std;
import binary;
import common;

let ARENA_REVISION = 0;

var prepared_data: u8[1000000] = [0; 1000000];

struct BufferHashBenchmark { size_val: i64, result_val: u32 }

fn prepare(base: BufferHashBenchmark&) {
    fill(prepared_data[..base.size_val], 0);
    for i in base.size_val { prepared_data[i] = next_int(256) as! u8; }
}

fn simple_sha256_digest(data: u8[:]) -> u8[32] {
    var result: u8[32] = [0; 32];
    var hashes: u32[8] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                          0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    for byte, i in data {
        let hash_idx = i % 8;
        var hash = hashes[hash_idx];
        hash = (hash << 5) + hash + byte;
        hash = (hash + (hash << 10)) ^ (hash >> 6);
        hashes[hash_idx] = hash;
    }
    for i in 8 {
        let hash = hashes[i];
        result[i * 4] = (hash >> 24) as! u8;
        result[i * 4 + 1] = (hash >> 16) as! u8;
        result[i * 4 + 2] = (hash >> 8) as! u8;
        result[i * 4 + 3] = hash as! u8;
    }
    return result;
}

fn run(s: BufferHashBenchmark&, iteration_id: i64) {
    let digest = simple_sha256_digest(prepared_data[..s.size_val]);
    let hash, ok = binary::read_u32le(digest, 0);
    s.result_val += hash;
}

fn main() {
    let size = bench_input();
    let iterations = bench_input();
    let warmups = bench_input();
    assert(size >= 1 && size <= 1000000 && iterations > 0 && warmups >= 0);
    reset();
    var s = BufferHashBenchmark { size_val: size, result_val: 0 };
    reset();
    prepare(s);
    for i in warmups { run(s, i); }
    reset();
    let count = bench_barrier(iterations);
    let started = bench_clock();
    for i in count { run(s, i); }
    let elapsed = bench_clock() - started;
    finish(s.result_val, elapsed, ARENA_REVISION);
}

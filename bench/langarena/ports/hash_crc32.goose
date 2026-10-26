// From LangArena goose/src/buffer_hash.goose; MIT, see LICENSE/README.md.
import std;
import common;

let ARENA_REVISION = 0;

var prepared_data: u8[1000000] = [0; 1000000];

struct BufferHashBenchmark { size_val: i64, result_val: u32 }

fn prepare(base: BufferHashBenchmark&) {
    fill(prepared_data[..base.size_val], 0);
    for i in base.size_val { prepared_data[i] = next_int(256) as! u8; }
}

fn crc32(data: u8[:]) -> u32 {
    var crc: u32 = 0xFFFFFFFF;
    for byte in data {
        crc ^= byte;
        for j in 8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    return crc ^ 0xFFFFFFFF;
}

fn run(s: BufferHashBenchmark&, iteration_id: i64) {
    let hash = crc32(prepared_data[..s.size_val]);
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

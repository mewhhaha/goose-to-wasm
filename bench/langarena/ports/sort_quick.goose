// From LangArena goose/src/sort.goose; MIT, see LICENSE/README.md.
import std;
import common;

let ARENA_REVISION = 0;

var prepared_data: i32[400000] = [0; 400000];
var working_data: i32[400000] = [0; 400000];

struct SortBenchmark { size_val: i64, result_val: u32 }

fn prepare(base: SortBenchmark&) {
    for i in base.size_val { prepared_data[i] = next_int(1000000); }
}

recursive fn quick_sort(arr: i32[:]) {
    if arr.len <= 1 { return; }
    let pivot = arr[arr.len / 2];
    var i = 0;
    var j = arr.len - 1;
    while i <= j {
        while arr[i] < pivot { i++; }
        while arr[j] > pivot { j--; }
        if i <= j {
            arr.swap_at(i, j);
            i++;
            j--;
        }
    }
    if j > 0 { quick_sort(arr[0..j + 1]); }
    if i < arr.len { quick_sort(arr[i..]); }
}

fn run(s: SortBenchmark&, iteration_id: i64) {
    s.result_val += prepared_data[next_int(s.size_val)] as! u32;
    // Preserve the full per-run copy, using the active bounded prefix.
    copy_into(working_data[..s.size_val], prepared_data[..s.size_val]);
    quick_sort(working_data[..s.size_val]);
    s.result_val += working_data[next_int(s.size_val)] as! u32;
}

fn main() {
    let size = bench_input();
    let iterations = bench_input();
    let warmups = bench_input();
    assert(size >= 1 && size <= 400000 && iterations > 0 && warmups >= 0);
    reset();
    var s = SortBenchmark { size_val: size, result_val: 0 };
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

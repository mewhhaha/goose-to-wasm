// From LangArena goose/src/sort.goose; MIT, see LICENSE/README.md.
import std;
import common;

let ARENA_REVISION = 0;

var prepared_data: i32[400000] = [0; 400000];
var working_data: i32[400000] = [0; 400000];
var merge_temp: i32[400000] = [0; 400000];

struct SortBenchmark { size_val: i64, result_val: u32 }

fn prepare(base: SortBenchmark&) {
    for i in base.size_val { prepared_data[i] = next_int(1000000); }
}

fn merge_sort_inplace(arr: i32[:]) {
    // Original temp.resize(arr.len, 0) initializes this on every invocation.
    fill(merge_temp[..arr.len], 0);
    merge_sort_helper(arr, merge_temp[..arr.len], 0, arr.len - 1);
}

recursive fn merge_sort_helper(arr: i32[:], temp: i32[:], left: i64, right: i64) {
    if left >= right { return; }
    let mid = (left + right) / 2;
    merge_sort_helper(arr, temp, left, mid);
    merge_sort_helper(arr, temp, mid + 1, right);
    merge(arr, temp, left, mid, right);
}

fn merge(arr: i32[:], temp: i32[:], left: i64, mid: i64, right: i64) {
    copy_into(temp[left..right + 1], arr[left..right + 1]);
    var i = left;
    var j = mid + 1;
    var k = left;
    while i <= mid && j <= right {
        if temp[i] <= temp[j] {
            arr[k] = temp[i];
            i++;
        } else {
            arr[k] = temp[j];
            j++;
        }
        k++;
    }
    while i <= mid {
        arr[k] = temp[i];
        i++;
        k++;
    }
}

fn run(s: SortBenchmark&, iteration_id: i64) {
    s.result_val += prepared_data[next_int(s.size_val)] as! u32;
    copy_into(working_data[..s.size_val], prepared_data[..s.size_val]);
    merge_sort_inplace(working_data[..s.size_val]);
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

// Scalar port of langbench's pinned C kernel. See manifest.json for provenance.
import std;

extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;

fn row_iterations(row: u32, n: u32, max_iter: u32, dx: f64, dy: f64) -> u64 {
    let ci = -1.25 + (row as f64 + 0.5) * dy;
    var sum: u64 = 0;
    var col: u32 = 0;
    while col < n {
        let cr = -2.0 + (col as f64 + 0.5) * dx;
        var zr: f64 = 0.0;
        var zi: f64 = 0.0;
        var iter: u32 = 0;
        while iter < max_iter {
            let zr2 = zr * zr;
            let zi2 = zi * zi;
            if zr2 + zi2 > 4.0 { break; }
            zi = 2.0 * zr * zi + ci;
            zr = zr2 - zi2 + cr;
            iter++;
        }
        sum += iter as u64;
        col++;
    }
    return sum;
}

fn main() {
    let input_n = bench_input();
    let input_iter = bench_input();
    let threads = bench_input();
    assert(input_n > 0 && input_n <= 4294967295);
    assert(input_iter > 0 && input_iter <= 4294967295);
    assert(threads == 1);
    let n = input_n as u32;
    let max_iter = input_iter as u32;
    let dx = (0.5 - -2.0) / n as f64;
    let dy = (1.25 - -1.25) / n as f64;
    var checksum: u64 = 0;
    var row: u32 = 0;
    let started = bench_clock();
    while row < n {
        checksum += row_iterations(row, n, max_iter, dx, dy);
        row++;
    }
    let elapsed = bench_clock() - started;
    print(checksum);
    print(elapsed);
}

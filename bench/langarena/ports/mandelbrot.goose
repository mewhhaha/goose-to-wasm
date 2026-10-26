// From LangArena goose/src/mandelbrot.goose; MIT, see LICENSE/README.md.
import std;
import common;

let ARENA_REVISION = 0;
let ITER = 50;
let LIMIT = 2.0;

// Retain every PBM image, including warmups: never replace this with a hash.
// 120 * (11-byte header + 400 rows * 50 bytes) = 2,401,320 bytes.
var result_bin: u8[2401320] = [0; 2401320];
var result_size: i64 = 0;

fn append_byte(value: u8) {
    assert(result_size < result_bin.len);
    result_bin[result_size] = value;
    result_size++;
}

fn append_text(text: u8[:]) { for byte in text { append_byte(byte); } }

// Bounded equivalent of format's positive decimal dimensions in the PBM header.
fn append_dimension(value: i64) {
    var digits: u8[20] = [0; 20];
    var len = 0;
    var remaining = value;
    loop {
        digits[len] = ('0' + remaining % 10) as u8;
        len++;
        remaining /= 10;
        if remaining == 0 { break; }
    }
    while len > 0 {
        len--;
        append_byte(digits[len]);
    }
}

struct Mandelbrot { w: i64, h: i64 }

fn run(s: Mandelbrot&, iteration_id: i64) {
    let w = s.w;
    let h = s.h;

    append_text("P4\n");
    append_dimension(w);
    append_byte(' ');
    append_dimension(h);
    append_byte('\n');

    var bit_num = 0;
    var byte_acc: u8 = 0;

    for y in h {
        let ci = 2.0 * y / h - 1.0;
        for x in w {
            var zr = 0.0;
            var zi = 0.0;
            var tr = 0.0;
            var ti = 0.0;
            let cr = 2.0 * x / w - 1.5;
            var i = 0;
            while i < ITER && tr + ti <= LIMIT * LIMIT {
                zi = 2.0 * zr * zi + ci;
                zr = tr - ti + cr;
                tr = zr * zr;
                ti = zi * zi;
                i++;
            }
            byte_acc <<= 1;
            if tr + ti <= LIMIT * LIMIT { byte_acc |= 0x01; }
            bit_num++;
            if bit_num == 8 {
                append_byte(byte_acc);
                byte_acc = 0;
                bit_num = 0;
            } else if x == w - 1 {
                byte_acc <<= 8 - w % 8;
                append_byte(byte_acc);
                byte_acc = 0;
                bit_num = 0;
            }
        }
    }
}

fn main() {
    let w = bench_input();
    let h = bench_input();
    let iterations = bench_input();
    let warmups = bench_input();
    assert(w >= 1 && w <= 400 && h >= 1 && h <= 400);
    assert(iterations > 0 && iterations <= 120 && warmups >= 0 && warmups <= 120);
    assert(iterations + warmups <= 120);
    reset();
    var s = Mandelbrot { w: w, h: h };
    reset();
    for i in warmups { run(s, i); }
    reset();
    let count = bench_barrier(iterations);
    let started = bench_clock();
    for i in count { run(s, i); }
    let elapsed = bench_clock() - started;
    finish(checksum_str(result_bin[..result_size]), elapsed, ARENA_REVISION);
}

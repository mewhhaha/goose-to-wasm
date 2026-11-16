//! Prints the host's float text for bit patterns read from stdin, one a line:
//! `f32 3f800000` or `f64 3ff0000000000000`. tests/float_text.py compares it
//! with `goose_float` of scripts/run_wasmtime.py.

use std::io::{BufRead, BufWriter, Write};

use goose_wasmtime::float::{f32_text, f64_text};

fn main() {
    let mut out = BufWriter::new(std::io::stdout().lock());
    for line in std::io::stdin().lock().lines() {
        let line = line.expect("stdin is text");
        let (kind, bits) = line.split_once(' ').expect("a line is a kind and its bits");
        let text = match kind {
            "f32" => f32_text(f32::from_bits(u32::from_str_radix(bits, 16).expect("f32 bits in hexadecimal"))),
            "f64" => f64_text(f64::from_bits(u64::from_str_radix(bits, 16).expect("f64 bits in hexadecimal"))),
            _ => panic!("unknown kind {kind}"),
        };
        writeln!(out, "{text}").expect("stdout takes the text");
    }
}

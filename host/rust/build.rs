//! Tells the host which Wasmtime it is built with (Cargo.lock has it), for
//! the `wasmtime` field of --timing-json.

use std::{env, fs, path::Path};

fn main() {
    let lock = Path::new(&env::var("CARGO_MANIFEST_DIR").expect("cargo sets the manifest directory")).join("Cargo.lock");
    println!("cargo:rerun-if-changed={}", lock.display());
    let text = fs::read_to_string(&lock).expect("Cargo.lock is beside Cargo.toml");
    let mut lines = text.lines();
    let version = loop {
        match lines.next() {
            Some("name = \"wasmtime\"") => {
                let line = lines.next().expect("a package has a version");
                break line.trim_start_matches("version = ").trim_matches('"');
            }
            Some(_) => {}
            None => panic!("Cargo.lock does not name wasmtime"),
        }
    };
    println!("cargo:rustc-env=GOOSE_WASMTIME_VERSION={version}");
}

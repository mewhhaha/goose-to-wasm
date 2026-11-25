//! A host for direct Goose WebAssembly modules on Wasmtime: the same imports,
//! output and exit codes as scripts/run_wasmtime.py, without Python.

pub mod blot;
pub mod float;
pub mod host;
pub mod pytext;
pub mod run;

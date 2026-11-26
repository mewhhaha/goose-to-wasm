// Compiler-internal deterministic multi-core pool interface.
// In plain Goose and Wasm targets these run serially with zero extra imports;
// the native C backend recognizes GP_COMPILER_PARALLEL_MARKER and backs the
// dispatch helpers with native/compiler_parallel.h.

let GP_COMPILER_PARALLEL_MARKER: i64 = 1;

fn gp_native_available() -> bool {
    return false;
}

fn gp_default_jobs() -> i64 {
    return 1;
}

fn gp_effective_jobs(requested: i64) -> i64 {
    if GP_COMPILER_PARALLEL_MARKER == 0 || !gp_native_available() { return 1; }
    if requested <= 0 {
        var n = gp_default_jobs();
        if n < 1 { n = 1; }
        if n > 16 { n = 16; }
        return n;
    }
    if requested > 32 { return 32; }
    return requested;
}

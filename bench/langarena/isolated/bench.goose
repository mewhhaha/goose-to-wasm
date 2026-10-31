// Only the isolated entrypoint supplies configuration. The unused upstream
// new_sieve function still resolves this symbol; accidentally calling it fails.
fn config_i64(name: const u8[:], key: const u8[:]) -> i64 {
    abort("configuration is supplied by the isolated harness");
}

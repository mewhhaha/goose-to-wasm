namespace adapter;
extern fn sidecar_value() -> i64;
fn value() -> i64 { sidecar_value() }

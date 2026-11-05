var owner: u8[>..] = [];
let view: const u8[:] = owner[..];
thread_fn worker() { print(view); }
fn main() { thread_wait(thread_spawn(worker)); }

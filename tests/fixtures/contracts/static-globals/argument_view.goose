thread_fn worker(value: const u8[:]) { print(value); }
fn main() { thread_wait(thread_spawn(worker, "abc")); }

var owner = 7;
let reference: const i64& = owner;
thread_fn worker() { print(reference); }
fn main() { thread_wait(thread_spawn(worker)); }

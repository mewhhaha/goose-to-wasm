var view: const u8[:] = "abc";
thread_fn worker() { print(view); }
fn main() { thread_wait(thread_spawn(worker)); }

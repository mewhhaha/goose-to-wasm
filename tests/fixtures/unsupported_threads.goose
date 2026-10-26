thread_fn worker() {}
fn main() { let id = thread_spawn(worker); thread_wait(id); }

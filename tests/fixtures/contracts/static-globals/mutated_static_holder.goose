struct Holder { value: const u8[:] }
let holder = Holder { "static" };
var owner: u8[>..] = [1];
fn change() { let p = &holder; p.value = owner[..]; }
thread_fn worker() { print(holder.value); }
fn main() { change(); thread_wait(thread_spawn(worker)); }

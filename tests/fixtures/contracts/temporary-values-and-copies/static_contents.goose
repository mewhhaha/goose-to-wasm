fn make() -> const u8[:][2] { ["one", "two"] }
fn main() { var keep: const u8[:] = ""; for value in make() { keep = value; } print(keep); }

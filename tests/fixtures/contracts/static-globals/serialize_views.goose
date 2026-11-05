fn main() { let views: const u8[:][2] = ["a", "b"]; let bytes = to_bytes(views); print(bytes); }

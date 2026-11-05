fn main() { let bytes: u8[2] = [98, 99]; var value: const u8[:] = bytes[..]; value = "static"; print(value); }

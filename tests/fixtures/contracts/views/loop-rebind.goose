fn main() { var value: const u8[:] = "static"; let bytes: u8[2] = [98, 99]; for i in 2 { value = bytes[..]; } print(value); }

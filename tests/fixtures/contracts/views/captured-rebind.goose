fn main() { var value: const u8[:] = "static"; let bytes: u8[2] = [98, 99]; fn change() { value = bytes[..]; } change(); print(value); }

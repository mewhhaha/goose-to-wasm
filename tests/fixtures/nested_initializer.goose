recursive fn target(take: bool) -> i64 {
    recursive fn leave(flag: bool) -> i64 {
        let a, b = 2, if flag { return 77 from target; } else { 3 };
        return a + b;
    }
    recursive fn relay(flag: bool) -> i64 {
        defer print("relay");
        let a, b = 2, leave(flag);
        return a + b;
    }
    return relay(take) + 10;
}

recursive fn captured(x: i64) -> i64 {
    recursive fn read() -> i64 {
        let a, b = 1, x;
        return a + b;
    }
    recursive fn pass() -> i64 {
        let a, b = 1, read();
        return a + b;
    }
    return pass();
}

fn main() {
    print(target(true));
    print(target(false));
    print(captured(2));
}

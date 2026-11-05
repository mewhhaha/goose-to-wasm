struct Pair { x: i16, y: i16 }
struct Body { value: Pair, tag: i64 }
fn main() {
    var body = Body { Pair { 2, 3 }, 99 };
    var calls = 0;
    fn location() -> Body& { calls += 1; return body; }
    fn scalar() -> i16 { assert(calls == 1); calls += 1; body.value = Pair { 50, 60 }; return 2; }
    location().value *= scalar();
    assert(calls == 2 && body.value == Pair { 4, 6 } && body.tag == 99);
    var first = [1, 2]; var second = [10, 20]; var target .= first;
    fn rebind() -> i64[2]& { target .= second; second[0] = 30; return second; }
    target += rebind();
    assert(first == [31, 22] && second == [30, 20] && target .== &second);
    var whole: const i64[2] = [1, 2]; whole += [3, 4]; whole *= 2;
    assert(whole == [8, 12]);
    print("compound ordering passed");
}

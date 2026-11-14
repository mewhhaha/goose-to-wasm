// A grow array of varint elements writes element images when it is pushed,
// appended, assigned or built from a literal, global or local. No other
// image type appears, so native C must still bring in its image runtime.
var global: varint[>..] = [];

fn main() {
    global.push(5); global.push(9223372036854775807); global.push(-300);
    print(global, " ", global.len);
    var local: varint[>..] = [];
    local.push(-9223372036854775808); local.push(127); local.push(128);
    print(local);
    var built: varint[>..] = [1, 2];
    built.append(local); built.push(0);
    print(built, " ", built.len);
    var total = 0;
    for x in built { total += x % 1000; }
    print(total);
    built = copy(global);
    print(built);
}

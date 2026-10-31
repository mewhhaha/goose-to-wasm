var canary: i64[>..] = [100];
fn main() {
    var outer = 0; var checks = 0; var total = 0;
    for i in 3 {
        var attempt = 0;
        while {
            checks++; attempt++;
            var scratch: i64[>..] = [attempt];
            if attempt < 3 { continue; }
            if attempt >= 5 { break; }
            scratch[0] > 0
        } {
            total += i * 10 + attempt;
        }
        outer++;
    }
    print(outer, " ", checks, " ", total, " ", canary[0]);
}

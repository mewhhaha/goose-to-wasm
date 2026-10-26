struct Inside { values: i64[..4] }

fn main() {
    var values: i64[..6] = [1, 2, 3, 4];
    let view = values[..4];
    let third: i64& = values[2];
    values.pop();
    print(third, " ", view);
    values.clear();
    print(third, " ", view);
    values = [8, 9];
    print(third, " ", view, " ", values.len);
    values.push(7);
    print(third, " ", view);
    values.resize(1);
    values.append(view);
    print(values, " ", view, " ", third);

    var nested: Inside[..3] = [Inside { [10, 20, 30, 40] }, Inside { [50, 60, 70, 80] }];
    let inside = nested[0].values[..4];
    let retained: i64& = nested[1].values[1];
    nested.clear();
    print(inside, " ", retained);
    nested.push(Inside { [1, 2, 3, 4] });
    print(inside, " ", retained);
    nested = [Inside { [11, 12, 13, 14] }];
    print(inside, " ", retained);
    nested.push(Inside { [21, 22, 23, 24] });
    print(inside, " ", retained);

    var runtime: i64[..] = [..4];
    runtime.append([1, 2]);
    let stale: i64& = runtime[1];
    let shorter: i64[..] = [7];
    runtime = copy(shorter);
    print(runtime, " ", runtime.cap, " ", stale);
    runtime.resize(2, 99);
    print(stale);

    var checksum = 0;
    for i in 10000 {
        var reused: Inside[..3] = [Inside { [i, i + 1] }, Inside { [i + 2, i + 3] }];
        let nested_ref: i64& = reused[1].values[1];
        reused.clear();
        checksum += nested_ref;
        reused = [Inside { [i + 4] }];
        checksum += nested_ref;
        reused.push(Inside { [i + 5, i + 6] });
        checksum += nested_ref;
    }
    print(checksum);
}

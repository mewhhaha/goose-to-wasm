// Adapted from upstream Goose samples/09_sorting.goose at revision
// 2e2bedef5b980bf013cac5aaa0095bfea64e5569. Kept insertion/merge/binary
// search and standard-library sorts; removed timing and reduced workloads
// to 10,000 random values; insertion sort still uses 20,000.
//
// Sorting and searching, written out: insertion sort, a recursive merge
// sort, and binary search, all over slices, so they work on any array kind
// and on any sub-range of one. Then the same jobs through the standard
// library over a small fixed sample. The merge sort shows the one rule
// recursion has in Goose: a recursive function owns no growable
// locals, so the scratch buffer belongs to the caller and is passed in.
//
// Build and run (from the repository root):
//   python scripts/goose_wasm.py build examples/sorting.goose --backend direct -o build/sorting.wasm

import std;

fn insertion_sort(xs: i32[:]) {
    for i in 1..xs.len {
        let v = xs[i];
        var j = i;
        while j > 0 && xs[j - 1] > v {
            xs[j] = xs[j - 1];
            j--;
        }
        xs[j] = v;
    }
}

// Sorts xs using tmp (at least as long) as scratch. Both halves are
// sub-slices. One caller-owned scratch buffer is reused throughout the
// recursion.
recursive fn merge_sort(xs: i32[:], tmp: i32[:]) {
    if xs.len <= 16 { insertion_sort(xs); return; }
    let mid = xs.len / 2;
    merge_sort(xs[..mid], tmp[..mid]);
    merge_sort(xs[mid..], tmp[mid..]);
    var i = 0;
    var j = mid;
    var k = 0;
    while i < mid && j < xs.len {
        if xs[j] < xs[i] { tmp[k] = xs[j]; j++; } else { tmp[k] = xs[i]; i++; }
        k++;
    }
    while i < mid { tmp[k] = xs[i]; i++; k++; }
    while j < xs.len { tmp[k] = xs[j]; j++; k++; }
    copy_into(xs, tmp[..xs.len]);
}

// The index of v in a sorted slice, or -1.
fn bsearch(xs: i32[:], v: i32) -> i64 {
    var lo = 0;
    var hi = xs.len;
    while lo < hi {
        let m = (lo + hi) / 2;
        if xs[m] < v { lo = m + 1; } else { hi = m; }
    }
    if lo < xs.len && xs[lo] == v { lo } else { -1 }
}

fn is_sorted(xs: i32[:]) -> bool {
    for i in 1..xs.len { if xs[i - 1] > xs[i] { return false; } }
    return true;
}

fn random_ints(n: i64, seed: u64) -> i32[>..] {
    var r = rng { seed };
    var xs: i32[>..] = [];
    for i in n { xs.push(r.rand_int(1000000) as i32); }
    return xs;
}

struct City { name: u8[..12], pop: i32 }

fn main() {
    // A small array, by hand.
    var small: i32[>..] = [5, 2, 9, 1, 5, 6, 3];
    insertion_sort(small);
    print(small, " ", is_sorted(small));
    print(bsearch(small, 6), " ", bsearch(small, 4), " ", bsearch(small, 1));
    // A sub-range: only the middle five are sorted.
    var part: i32[>..] = [9, 8, 7, 6, 5, 4, 3, 2, 1];
    insertion_sort(part[2..7]);
    print(part);

    // A deterministic sample workload, three ways. The scratch is one buffer
    // for the whole recursion, made once.
    let n = 10000;
    var a = random_ints(n, 1);
    var scratch: i32[>..] = [];
    scratch.resize(n, 0);
    merge_sort(a, scratch);
    print(is_sorted(a), " ", a[0], " ", a[n / 2], " ", a[n - 1]);

    var b = random_ints(n, 1);
    sort(b);                             // the library's quicksort
    var same = a.len == b.len;
    for i in a.len { if a[i] != b[i] { same = false; } }
    print(same);

    var c = random_ints(20000, 1);
    insertion_sort(c);
    print(is_sorted(c));

    // Searching the sorted sample: a hand-written and the library search
    // agree, on hits and on misses.
    var hits = 0;
    var agree = true;
    for i in 0..1000 {
        let v = (i * 997) as i32;
        let k = bsearch(a, v);
        let k2, found = binary_search(a, v);
        if k >= 0 { hits++; }
        if (k >= 0) != found { agree = false; }
    }
    print(hits, " hits, agree ", agree);

    // Structs sort by a comparator; stable_sort keeps equal keys in their
    // original order, which matters when sorting by one field of several.
    var cities: City[>..] = [];
    cities.push(City { name: "oslo", pop: 700 });
    cities.push(City { name: "lima", pop: 9700 });
    cities.push(City { name: "bern", pop: 130 });
    cities.push(City { name: "rome", pop: 2800 });
    cities.push(City { name: "riga", pop: 600 });
    sort(cities) { a, b => a.pop > b.pop };
    for c in cities { print("  ", c.name, " ", c.pop); }
    stable_sort(cities) { a, b => a.name[0] < b.name[0] };   // by first letter only
    for c in cities { print("  ", c.name, " ", c.pop); }
}

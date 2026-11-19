"""Array lifetime checks across mutations and repeated calls."""
import subprocess
import unittest

from tests import goose_stats


class HolderWalks(goose_stats.Compile, unittest.TestCase):
    def test_mixed_owner_replay_preserves_read_before_shrink(self):
        source = self.work / "mixed_owners.goose"
        source.write_text("""fn reset(xs: i64[>..<]&) {
    var local: i64[>..<] = [];
    let target: i64[>..<]& = if xs.len > 0 { &xs } else { &local };
    let length = target.len;
    target = [length];
}
fn twice(xs: i64[>..<]&) { reset(xs); reset(xs); }
recursive fn outer(again: bool) -> i64 {
    var xs: i64[>..<] = [];
    twice(xs);
    if again { xs = [outer(false)]; }
    return 0;
}
fn main() { outer(true); }
""")
        result = subprocess.run([goose_stats.GOOSE, source, "--check"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        # The recursive call replays reset's read of target before its assignment.
        self.assertRegex(result.stderr, r"(?s)whole assignment reads storage.*array shrink invalidates")

    def test_repeated_shrinks(self):
        program = """struct Holder { view: const i64[:], tag: i64 = 0 }
struct Outer { holder: Holder& }
fn main() {
    var xs: i64[>..] = [1, 2, 3];
    var ys: i64[>..] = [4, 5, 6];
    var holder = Holder { view: ys[0..1] };
    var outer = Outer { holder: holder };
    xs.pop();
    xs.pop();
    UPDATE
    xs.pop();
    print(outer.holder.view[0]);
}
"""
        source = self.work / "holder.goose"
        for update, status in [("holder.view = xs[0..1];", 1),
                               ("holder.view = ys[0..1];", 0), ("holder.tag = 42;", 0)]:
            with self.subTest(update=update):
                source.write_text(program.replace("UPDATE", update))
                result = subprocess.run([goose_stats.GOOSE, source, "--check"], capture_output=True, text=True)
                self.assertEqual(result.returncode, status, result.stderr)
                if status:
                    self.assertIn("array shrink invalidates a reference or holder", result.stderr)

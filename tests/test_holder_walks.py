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

    def test_class_transition_preserves_standalone_arguments_and_errors(self):
        source = self.work / "class_transition.goose"
        # A call past the 4,096-frame concrete limit needs the full read history.
        functions = [f"fn call_{i}() -> i64 {{ {i} }}" for i in range(4100)]
        calls = [f"    call_{i}();" for i in range(len(functions))]
        program = "\n".join([
            "fn standalone(xs: const i64[:], tag: i64&) -> i64 { xs.len + tag }",
            *functions,
            "fn last(xs: i64[>..<]&) -> i64 {",
            "    let view = xs[0..1];",
            "    MUTATE",
            "    return view[0];",
            "}",
            "fn main() {",
            *calls,
            "    var xs: i64[>..<] = [42, 7];",
            "    print(last(xs));",
            "}",
        ])
        for mutation, status in [("", 0), ("xs.pop();", 1)]:
            with self.subTest(mutation=mutation):
                source.write_text(program.replace("MUTATE", mutation))
                result = subprocess.run([goose_stats.GOOSE, source, "--check"], capture_output=True, text=True)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(result.stderr.count("array shrink invalidates"), status, result.stderr)

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

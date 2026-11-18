"""Compare both region planners on ordered diagnostics and function bounds."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("compiler", type=Path)
parser.add_argument("commits", nargs=2)
args = parser.parse_args()
repo = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
compiler = args.compiler.resolve()
results = []
for commit in args.commits:
    work = args.output.resolve() / commit
    work.mkdir(parents=True)
    planner = subprocess.check_output(["git", "show", f"{commit}:selfhost/region_plan.goose"], cwd=repo)
    (work / "region_plan.goose").write_bytes(planner)
    (work / "model.goose").write_text("""struct Node { token: i64 }
struct Program { nodes: Node[>..]& }
fn diagnose(p: Program&, token: i64, message: u8[:]) { print(token, " ", message); }
""")
    (work / "main.goose").write_text("""import region_plan;
import model;
fn advance(state: i64&) -> i64 { state = (48271 * state) % 2147483647; return state; }
fn main() {
    var state: i64 = 917; var nodes: Node[>..] = [];
    for i in 0..80 { nodes.push(Node { token: i }); }
    var p = Program { nodes: nodes };
    for trial in 0..256 {
        var functions: RegionFunction[>..] = []; var calls: RegionCall[>..] = [];
        var stack: i64[>..] = []; var members: i64[>..] = [];
        let size = advance(state) % 25;
        for i in 0..size { functions.push(RegionFunction { own: advance(state) % 17, entry: (i % 5) == 0 }); }
        var graph = RegionGraph { functions: functions, calls: calls, stack: stack, members: members };
        for pass in 0..2 {
            let extra = advance(state) % 80;
            for i in 0..extra {
                let caller = advance(state) % (size + 2) - 1;
                let callee = advance(state) % (size + 2) - 1;
                var live = advance(state) % 4;
                if i == 7 { live = 9223372036854775807; }
                calls.push(RegionCall { caller: caller, callee: callee, live: live, node: i });
            }
            print(trial, " ", pass, " ", region_bound(p, graph, 3));
            for f in functions { print(f.component, " ", f.need); }
        }
    }
}
""")
    subprocess.run([compiler, "main.goose", "--stdlib", repo/"stdlib", "--target", "native", "-O2", "-o", "test.c"], check=True, cwd=work)
    subprocess.run(["cc", "-w", "-O2", "test.c", "-lm", "-ldl", "-pthread", "-o", "test"], check=True, cwd=work)
    data = subprocess.check_output([work/"test"], cwd=work)
    (work/"observed.txt").write_bytes(data)
    results.append(dict(commit=commit, lines=len(data.splitlines()), sha256=hashlib.sha256(data).hexdigest()))
assert results[0]["lines"] > 256 and results[0]["sha256"] == results[1]["sha256"]
print(json.dumps({"seed": 917, "graphs": 256, "plans_per_graph": 2, "results": results}, indent=2))

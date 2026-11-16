"""gdbhook.py DIR (after progress.py): call a function gdb can break on for one
in 2,503 new sets once 5,000 frames exist. Build with -fno-inline, find the
function's number in the --wasm-stats names (it is g_fn<id> in the C), and run
gdb -q -batch -x gdbcmds.txt EXE; gdbstacks.py aggregates the backtraces."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
s = s.replace('import model;', 'import model;\nvar dbg_newsets: i64 = 0; var dbg_newset_hits: i64 = 0;\nrecursive fn dbg_newset(count: i64) { if count < -5 { dbg_newset(count + 1); } dbg_newset_hits += count; }', 1)
old = "    let index = l.sets.len; l.sets.push(LifeSet { first: next, count: count });"
assert s.count(old) == 1
s = s.replace(old, "    dbg_newsets += 1; if dbg_newsets % 2503 == 0 && l.frames.len > 5000 { dbg_newset(count); }\n" + old)
open(f, 'w').write(s)

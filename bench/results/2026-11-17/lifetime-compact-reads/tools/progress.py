#!/usr/bin/env python3
"""progress.py SELFHOST_COPY: print 'LIFEPROG frames N ms T effects E' to stderr every 1,000 new frames of the lifetime pass."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'; s = open(f).read()
def rep(old, new):
    global s
    assert s.count(old) == 1, (old[:80], s.count(old)); s = s.replace(old, new)
s = s.replace('import model;', 'import model;\nimport os;', 1)
rep("""    if function_node < 0 || p.nodes[function_node].right < 0 { return LifeValue {}; }
    var lexical = 0;""", """    if function_node < 0 || p.nodes[function_node].right < 0 { return LifeValue {}; }
    if l.frames.len >= dbg_next_frames { dbg_next_frames += 1000; print("LIFEPROG frames ", l.frames.len, " ms ", (clock_ns() - dbg_start) / 1000000, " effects ", l.effects.len, " class ", l.class_frames); }
    var lexical = 0;""")
rep("\nfn check_lifetimes(", "\nvar dbg_next_frames: i64 = 1000; var dbg_start: i64 = 0;\nfn check_lifetimes(")
rep("""    // Standalone argument synthesis is complete; evaluation only reads types.
    l.types_frozen = true;""", """    // Standalone argument synthesis is complete; evaluation only reads types.
    l.types_frozen = true; dbg_start = clock_ns();""")
open(f, 'w').write(s); print('progress lines every 1,000 frames')

#!/usr/bin/env python3
"""valcount.py FILE: validation counters on top of the sp-work3 instrumentation."""
import sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new):
    global t
    assert t.count(old) == 1, (old[:60], t.count(old)); t = t.replace(old, new)
rep("var dbg_shrink_ns: i64 = 0;", "var dbg_kinds: i64[16] = [0; 16]; var dbg_kind_ns: i64[16] = [0; 16]; var dbg_noholds: i64 = 0; var dbg_vfar: i64 = 0; var dbg_vframes: i64 = 0; var dbg_vfound2: i64 = 0; var dbg_vfound1: i64 = 0; var dbg_vnew: i64 = 0; var dbg_vcalls: i64 = 0; var dbg_direct: i64 = 0;\nvar dbg_shrink_ns: i64 = 0;")
rep("""        if effect.kind == 1 { life_shrink(p, l, effect.node, effect.value); }
        else if effect.kind == 2 { life_grow(p, l, effect.node, effect.value); }
        else if effect.kind == 3 { life_construct_read(p, l, effect.node, effect.value, leaf); }
        else if effect.kind == 8 { life_replace(p, l, effect.node, effect.value); }""",
"""        var dbg_t0 = 0; if !l.discovery { dbg_kinds[effect.kind] += 1; dbg_t0 = clock_ns(); if l.hold_floor == l.hold_count { dbg_noholds += 1; } }
        if effect.kind == 1 { life_shrink(p, l, effect.node, effect.value); }
        else if effect.kind == 2 { life_grow(p, l, effect.node, effect.value); }
        else if effect.kind == 3 { life_construct_read(p, l, effect.node, effect.value, leaf); }
        else if effect.kind == 8 { life_replace(p, l, effect.node, effect.value); }
        if !l.discovery && (effect.kind <= 3 || effect.kind == 8) { dbg_kind_ns[effect.kind] += clock_ns() - dbg_t0; }""")
rep("""                let found = life_effect_indexed(l, effect, frame, life_index_bucket(l, indexed), outside);""",
"""                let found = life_effect_indexed(l, effect, frame, life_index_bucket(l, indexed), outside);
                if effect.kind == 3 { dbg_vframes += 1; if found == 2 { dbg_vfound2 += 1; } else if found == 1 { dbg_vfound1 += 1; } else { dbg_vnew += 1; } }""")
rep("""    let reach = life_effect_far(l, effect); let far = reach.far;""", """    if !l.discovery && effect.kind == 3 { dbg_vcalls += 1; }
    let reach = life_effect_far(l, effect); let far = reach.far;""")
rep("""    print("DBG validation ms",""", """    print("DBG validation replay kinds", dbg_kinds[1], dbg_kinds[2], dbg_kinds[3], dbg_kinds[4], dbg_kinds[5], dbg_kinds[6], dbg_kinds[7], dbg_kinds[8], dbg_kinds[9], " ms by kind 1,2,3,8:", dbg_kind_ns[1] / 1000000, dbg_kind_ns[2] / 1000000, dbg_kind_ns[3] / 1000000, dbg_kind_ns[8] / 1000000, " no holds", dbg_noholds);
    print("DBG validation kind-3 offers", dbg_vcalls, " frames probed", dbg_vframes, " found2", dbg_vfound2, " found1", dbg_vfound1, " new", dbg_vnew);
    print("DBG validation ms",""")
open(p, 'w').write(t); print('applied')

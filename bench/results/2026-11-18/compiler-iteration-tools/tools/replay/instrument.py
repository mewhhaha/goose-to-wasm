"""Instrument the ba9dece Goose lifetime replay. Expects a scratch compiler tree."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("tree", type=Path)
args = parser.parse_args()
path = args.tree / "selfhost/checker_lifetimes.goose"
source = path.read_text()

def replace(s, a, b, n=1):
    assert s.count(a) == n, (s.count(a), n, a)
    return s.replace(a,b)

# The two in-place effect merge sites already compare every growing effect set.
source = replace(source, "|| !life_equal(l, value_places, old_place) { l.revision += 1; }", "|| !life_equal(l, value_places, old_place) { lp_merges += 1; l.revision += 1; }")
source = replace(source, "|| !life_equal(l, place, value.place) { l.revision += 1; }", "|| !life_equal(l, place, value.place) { lp_merges += 1; l.revision += 1; }")
start=source.index("fn life_replay(")
end=source.index("// Persist the final root proof",start)
r=source[start:end]
preamble="""// Diagnostic counts per phase and effect kind. Classify each visit once.
var lp_vis: i64[20]; var lp_summary: i64[20]; var lp_leaf: i64[20]; var lp_filtered: i64[20];
var lp_applied: i64[20]; var lp_added: i64[20]; var lp_updated: i64[20]; var lp_productive: i64[20];
var lp_revision_only: i64[20]; var lp_new_visits: i64[20]; var lp_merge_visits: i64[20];
var lp_calls: i64[2]; var lp_chains: i64[2]; var lp_bypassed: i64[2]; var lp_unquantified: i64[2];
var lp_mapped: i64[20]; var lp_map_context: i64[20]; var lp_merges: i64 = 0; var lp_depth: i64 = 0; var lp_max_depth: i64 = 0;
fn lp_apply(l: Lifetimes&, k: i64, before_add: i64, before_merge: i64, revision: i64) {
    let add = l.effects.len + l.summary_reads.len - before_add; let changed = lp_merges - before_merge;
    lp_applied[k]++; lp_added[k] += add; lp_updated[k] += changed;
    if add > 0 { lp_new_visits[k]++; }
    if changed > 0 { lp_merge_visits[k]++; }
    if add > 0 || changed > 0 { lp_productive[k]++; }
    else if revision != l.revision { lp_revision_only[k]++; }
}
fn lp_print() {
    for phase in 0..2 {
        print("REPLAY_CALLS ", phase, " ", lp_calls[phase], " ", lp_chains[phase], " ", lp_bypassed[phase], " ", lp_unquantified[phase], " ", lp_max_depth);
        for kind in 0..10 {
            let k=phase*10+kind;
            if lp_vis[k] > 0 {
                print("REPLAY_ROW ", phase, " ", kind, " ", lp_vis[k], " ", lp_summary[k], " ", lp_leaf[k], " ", lp_filtered[k], " ", lp_applied[k], " ", lp_productive[k], " ", lp_new_visits[k], " ", lp_merge_visits[k], " ", lp_added[k], " ", lp_updated[k], " ", lp_revision_only[k], " ", lp_map_context[k], " ", lp_mapped[k]);
            }
        }
    }
}
"""
r=replace(r,"    var at =", """    var phase: i64 = 0; if !l.discovery { phase = 1; }
    lp_calls[phase]++; lp_depth++; if lp_depth > lp_max_depth { lp_max_depth = lp_depth; }
    var at =""")
r=replace(r,"    if others { at =", """    if others {
        lp_chains[phase]++; if l.compact { lp_bypassed[phase] += l.frames[frame].read_count; } else { lp_unquantified[phase]++; }
        at =""")
r=replace(r,"            if (memo || quick) && life_leaf_offered(l, leaf) { continue; }", """            let k=phase*10+3; lp_vis[k]++; if m.count > 0 { lp_map_context[k]++; }
            if (memo || quick) && life_leaf_offered(l, leaf) { lp_leaf[k]++; continue; }""")
r=replace(r,"            life_construct_read(p, l, node, value, known);", """            let adds = l.effects.len + l.summary_reads.len; let merges = lp_merges; let revision = l.revision;
            life_construct_read(p, l, node, value, known);
            lp_apply(l, k, adds, merges, revision);""")
r=replace(r,"        passed = at; open = read >= 0;", """        passed = at; open = read >= 0;
        let k=phase*10+l.effects[at].kind; lp_vis[k]++; if m.count > 0 { lp_map_context[k]++; }""")
r=replace(r,"                at = s.after; if others", "                lp_summary[k]++; at = s.after; if others")
r=replace(r,"{ at = s.after; continue; }","{ lp_leaf[k]++; at = s.after; continue; }",2)
r=replace(r,"if life_leaf_offered(l, leaf) { at = next; continue; }","if life_leaf_offered(l, leaf) { lp_leaf[k]++; at = next; continue; }",2)
r=replace(r,"if effect.value.contents == 0 { at = next; continue; }","if effect.value.contents == 0 { lp_filtered[k]++; at = next; continue; }")
r=replace(r,"if mapped { effect.places", "if mapped { lp_mapped[k]++; effect.places")
r=replace(r,"s.replayed_epoch == epoch { at = next; continue; }","s.replayed_epoch == epoch { lp_summary[k]++; at = next; continue; }")
r=replace(r,"        if effect.kind == 1 { life_shrink", """        let adds=l.effects.len+l.summary_reads.len; let merges=lp_merges; let revision=l.revision;
        if effect.kind == 1 { life_shrink""")
r=replace(r,"        if remembered && l.offer_count", "        lp_apply(l, k, adds, merges, revision);\n        if remembered && l.offer_count")
r=replace(r,"    if complete && l.frames[frame].reads_version == version", "    lp_depth--;\n    if complete && l.frames[frame].reads_version == version")
source=source[:start]+preamble+r+source[end:]
needle="    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }"
source=replace(source,needle,needle+"\n    lp_print();")
path.write_text(source)

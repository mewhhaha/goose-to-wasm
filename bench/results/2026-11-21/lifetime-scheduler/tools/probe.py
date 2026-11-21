#!/usr/bin/env python3
"""Add diagnostic timers and a read-only scheduler predictor to a source copy."""
import argparse
from pathlib import Path


def patch(source, mode):
    def replace(old, new):
        nonlocal source
        assert source.count(old) == 1, old
        source = source.replace(old, new)

    replace("import model;", "import model;\nimport os;")
    replace("        if !life_check_roots(p, l, standalone, omit_reads) { return false; }\n        if l.failures.len",
            """        let elapsed_at = clock_ns();
        if !life_check_roots(p, l, standalone, omit_reads) { return false; }
        print("round ", l.pass, " ", clock_ns() - elapsed_at);
        if l.failures.len""")
    replace("    if !life_check_roots(p, l, standalone, omit_reads) { return false; }\n    l.types_frozen = false;",
            """    let validation_at = clock_ns();
    if !life_check_roots(p, l, standalone, omit_reads) { return false; }
    print("validate ", clock_ns() - validation_at);
    l.types_frozen = false;""")
    if mode == "control":
        return source
    if mode == "validation":
        replace("struct Lifetimes {", """struct Lifetimes {
    trial_capture_ns: i64 = 0, trial_capture_count: i64 = 0,
    trial_replay_ns: i64 = 0, trial_replay_count: i64 = 0,""")
        replace("    var items = LifeItemList {}; var enclosing = lexical;",
                "    let capture_at = clock_ns();\n    var items = LifeItemList {}; var enclosing = lexical;")
        replace("    return items.first;\n}\n// A call of a top-level function by the classes of its arguments.",
                """    l.trial_capture_ns += clock_ns() - capture_at;
    l.trial_capture_count += 1;
    return items.first;
}
// A call of a top-level function by the classes of its arguments.""")
        replace("    if l.watch_stores && summary {",
                """    let replay_measured = !summary && !l.discovery;
    var replay_at: i64 = 0; if replay_measured { replay_at = clock_ns(); }
    if l.watch_stores && summary {""")
        replace("    if complete && l.frames[frame].replay_version == version { life_chain_replay(l, chain, version); }",
                """    if complete && l.frames[frame].replay_version == version { life_chain_replay(l, chain, version); }
    if replay_measured { l.trial_replay_ns += clock_ns() - replay_at; l.trial_replay_count += 1; }""")
        replace('    print("validate ", clock_ns() - validation_at);',
                '''    print("validate ", clock_ns() - validation_at);
    print("validation_detail ", l.trial_capture_count, " ", l.trial_capture_ns, " ", l.trial_replay_count, " ", l.trial_replay_ns);''')
        return source

    replace("struct Lifetimes {", """struct TrialFrame {
    pass: i64 = 0, parent: i64 = -1, context: i64 = -1, site: i64 = -1, destination: i64 = -1,
    clean: bool = false, live: i64 = 0
}
struct Lifetimes {
    trial_frames: TrialFrame[>..]&,
    trial_calls: i64 = 0, trial_live: i64 = 0, trial_entries_changed: i64 = 0,
    trial_measured: i64 = 0, trial_leaf_count: i64 = 0, trial_leaf_ns: i64 = 0,
    trial_clean_count: i64 = 0, trial_clean_ns: i64 = 0,
    trial_predicted: i64 = 0, trial_rejected: i64 = 0, trial_predicted_ns: i64 = 0, trial_ordered_ns: i64 = 0,""")
    replace("    var store_wakes: LifeStoreWake[>..] = [];",
            "    var trial_frames: TrialFrame[>..] = [];\n    var store_wakes: LifeStoreWake[>..] = [];")
    replace("bodies: bodies, body_slots:", "trial_frames: trial_frames, bodies: bodies, body_slots:")
    replace("    if l.cells[cell].live == live { return; }",
            """    if l.cells[cell].live == live { return; }
    if l.discovery && l.omit_construct_reads && l.class_frames == 0 {
        l.trial_live += 1;
        if l.frame < l.trial_frames.len && l.cells[cell].frame == l.frame { l.trial_frames[l.frame].live += 1; }
    }""")
    replace("    var lexical = 0;\n    if p.nodes[function_node].symbol >= 0 {",
            """    if l.discovery && l.omit_construct_reads { l.trial_calls += 1; }
    var lexical = 0;
    if p.nodes[function_node].symbol >= 0 {""")
    # Count frame changes even on same-pass replay. Capture the old state before
    # overwriting the context and compare after lifetimes has computed the new one.
    replace("        l.frames[target].parent = previous_frame; l.frames[target].destination = destination;",
            """        let context_before = l.frames[target].context;
        let home_changed = l.frames[target].parent != previous_frame || l.frames[target].destination != destination;
        l.frames[target].parent = previous_frame; l.frames[target].destination = destination;""")
    replace("        l.frames[target].context = life_context(l, target, l.frames[previous_frame].context);",
            """        l.frames[target].context = life_context(l, target, l.frames[previous_frame].context);
        if l.discovery && l.omit_construct_reads && (home_changed || context_before != l.frames[target].context) {
            l.trial_entries_changed += 1;
        }""")
    replace("        life_eval(p, l, p.nodes[function_node].right, destination, selected_result);",
            """        if l.discovery && l.omit_construct_reads && l.class_frames == 0 {
            while l.trial_frames.len <= target { l.trial_frames.push(TrialFrame {}); }
            let old = l.trial_frames[target]; let context = l.frames[target].context;
            let predicts = l.pass >= 2 && old.pass == l.pass - 1 && old.clean &&
                old.parent == previous_frame && old.context == context && old.site == call && old.destination == destination;
            let entries = l.trial_entries_changed; let external = l.trial_live - old.live;
            let invokes = l.trial_calls; let revision = l.revision;
            let frames = l.frames.len; let cells = l.cells.len; let roots = l.roots.len; let exits = l.exits.len;
            let failures = l.failures.len; let result = l.frames[target].result; let effects = l.frames[target].replay_version;
            let covered = l.trial_clean_ns; let projected = l.trial_predicted_ns; let ordered_before = l.trial_ordered_ns;
            let epoch = l.recursion_epoch;
            let began = clock_ns();
            life_eval(p, l, p.nodes[function_node].right, destination, selected_result);
            let spent = clock_ns() - began;
            l.trial_measured += 1;
            if l.trial_calls == invokes {
                l.trial_leaf_count += 1; l.trial_leaf_ns += spent;
            }
            let ordered = l.class_frames == 0 && external == l.trial_live - l.trial_frames[target].live &&
                entries == l.trial_entries_changed && epoch == l.recursion_epoch &&
                frames == l.frames.len && cells == l.cells.len && roots == l.roots.len;
            if ordered { l.trial_ordered_ns = ordered_before + spent; }
            let clean = ordered && revision == l.revision && exits == l.exits.len &&
                failures == l.failures.len && effects == l.frames[target].replay_version &&
                life_round_value(l, result, l.frames[target].result);
            if clean {
                l.trial_clean_count += 1;
                l.trial_clean_ns = covered + spent;
            }
            if predicts {
                l.trial_predicted += 1;
                if clean { l.trial_predicted_ns = projected + spent; }
                else { l.trial_rejected += 1; }
            }
            l.trial_frames[target] = TrialFrame { pass: l.pass, parent: previous_frame, context: context,
                site: call, destination: destination, clean: clean, live: l.trial_frames[target].live };
        } else {
            life_eval(p, l, p.nodes[function_node].right, destination, selected_result);
        }""")
    replace("        let elapsed_at = clock_ns();",
            """        l.trial_measured = 0; l.trial_leaf_count = 0; l.trial_leaf_ns = 0;
        l.trial_clean_count = 0; l.trial_clean_ns = 0; l.trial_predicted = 0; l.trial_rejected = 0; l.trial_predicted_ns = 0; l.trial_ordered_ns = 0;
        let elapsed_at = clock_ns();""")
    replace('        print("round ", l.pass, " ", clock_ns() - elapsed_at);',
            '''        print("round ", l.pass, " ", clock_ns() - elapsed_at);
        print("shadow ", l.pass, " ", l.class_frames, " ", l.trial_measured, " ", l.trial_leaf_count,
              " ", l.trial_leaf_ns, " ", l.trial_clean_count, " ", l.trial_clean_ns, " ",
              l.trial_predicted, " ", l.trial_rejected, " ", l.trial_predicted_ns, " ", l.trial_ordered_ns);''')
    if mode == "audit":
        replace("fn life_round_cell(", (Path(__file__).with_name("audit.inc").read_text() + "\nfn life_round_cell("))
        replace("            let entries = l.trial_entries_changed;", """            var before: u64 = 0;
            if predicts { before = trial_state(l, target); }
            let entries = l.trial_entries_changed;""")
        replace("            if clean {\n                l.trial_clean_count", """            var unchanged = clean;
            if predicts && clean {
                unchanged = before == trial_state(l, target);
                if !unchanged { print("mismatch ", l.pass, " ", target, " ", function_node, " ", call); }
            }
            if clean {
                l.trial_clean_count""")
        replace("if clean { l.trial_predicted_ns = projected + spent; }",
                "if unchanged { l.trial_predicted_ns = projected + spent; }")
    return source


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("mode", choices=("control", "shadow", "validation", "audit"))
    options = parser.parse_args()
    options.source.write_text(patch(options.source.read_text(), options.mode))

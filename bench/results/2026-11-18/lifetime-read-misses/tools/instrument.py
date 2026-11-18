"""Add a scoped CPU-sampling marker or exact event counters to a scratch Goose compiler."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("tree", type=Path)
parser.add_argument("mode", choices=("phases", "counts", "outer"))
args = parser.parse_args()
path = args.tree / "selfhost/checker_lifetimes.goose"
source = path.read_text()

def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"expected one matching site: {old}")
    return text.replace(old, new)

def body(name):
    start = source.index("fn " + name + "(")
    end = source.index("\n}", start) + 2
    return source[start:end].replace("fn " + name + "(", "fn probe_" + name + "(")

def phase(n):
    if args.mode == "phases":
        return f"mp_marker[8] = {n}; "
    return ""

def count(n):
    if args.mode == "counts":
        return f"mp_counts[{n}]++; "
    return ""

def merge_phase(n):
    if args.mode == "phases":
        return f"mp_marker[8] = merge_base + {n}; "
    return ""

construct = body("life_construct_read").replace("life_offer_once(l,", "probe_life_offer_once(l,")
offer_once = body("life_offer_once").replace("life_read_offer(l,", "probe_life_read_offer(l,")
offer = body("life_read_offer").replace("life_read_merge(l,", "probe_life_read_merge(l,")
merge = body("life_read_merge")
offer_once = once(offer_once, "if compact { far = probe_life_read_offer(l, leaf, offer); }",
                  "if compact { " + count(1) + "far = probe_life_read_offer(l, leaf, offer); " + phase(1) + "}")
offer = once(offer, "let reach = life_effect_far(l, effect);", phase(2) + "let reach = life_effect_far(l, effect); " + phase(3))
offer = once(offer, "sent as i64 == context { return far; }", "sent as i64 == context { " + count(2) + "return far; }")
offer = once(offer, "var frame = l.frame;", phase(4) + "var frame = l.frame;")
offer = once(offer, "while frame > 0 {", "while frame > 0 { " + count(3))
offer = once(offer, "if merged == 2 {", phase(4) + "if merged == 2 {")
offer = once(offer, "if own < 0 { own = life_read_find", phase(3) + "if own < 0 { own = life_read_find")
# Indexes 5..8 belong to merges into the offering frame, 9..12 to caller frames.
base_decl = "var merge_base: u8 = 5; if frame != l.frame { merge_base = 9; } "
merge = once(merge, "let walked = life_walked", base_decl + merge_phase(0) + count("merge_base as i64") + "let walked = life_walked")
merge = once(merge, "life_read_add(l,", merge_phase(1) + count("merge_base as i64 + 1") + "life_read_add(l,")
merge = once(merge, "let seen = l.summary_reads", merge_phase(2) + count("merge_base as i64 + 2") + "let seen = l.summary_reads")
merge = once(merge, "let held = l.summary_reads", merge_phase(3) + count("merge_base as i64 + 3") + "let held = l.summary_reads")
merge = once(merge, "{ l.revision += 1; }", "{ " + count("13 + (merge_base as i64 - 5) / 4") + "l.revision += 1; }")
trigger = "life_construct_read(p, l, l.leaves[leaf].node, l.leaves[leaf].value, leaf);"
grouped = "fn life_replay_group(" in source
if not grouped:
    trigger = "life_construct_read(p, l, node, value, known);"
enter, leave = phase(1), phase(0)
if args.mode == "outer":
    enter, leave = "mp_marker[8] = 1; ", "mp_marker[8] = 0; "
instrumented = enter + count(0) + trigger.replace("life_construct_read(", "probe_life_construct_read(") + " " + leave
if not grouped:
    instrumented = ("if chain >= 0 && l.frames[frame].read_count >= 8 { " + instrumented + "} else { " + trigger + " }")
source = once(source, trigger, instrumented)
globals_ = "var mp_marker: u8[9] = [77, 80, 83, 65, 77, 80, 76, 69, 0];\n"
if args.mode == "counts":
    globals_ = "var mp_counts: i64[15];\n"
source += "\n" + globals_ + "\n\n".join((construct, offer_once, offer, merge)) + "\n"
start = source.index("fn check_lifetimes(")
at = source.index("\n", start)
tail = "    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }"
if args.mode != "counts":
    source = source[:at] + "\n    write_stdout(mp_marker[..]);" + source[at:]
    source = once(source, tail, tail + '\n    write_stdout("MPFINISH");')
else:
    source = once(source, tail, tail + '\n    print("MISS_COUNTS ", mp_counts);')
path.write_text(source)

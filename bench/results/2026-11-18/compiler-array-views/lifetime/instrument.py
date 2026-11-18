"""Count readback work, or compare every adaptive memo hit against full evaluation."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path, help="scratch compiler source directory")
parser.add_argument("mode", choices=["baseline", "adaptive", "shadow"])
args = parser.parse_args()
path = args.source / "selfhost/checker_lifetimes.goose"
source = path.read_text()


def insert(before, replacement):
    global source
    if source.count(before) != 1:
        raise ValueError(f"expected one occurrence of {before!r}")
    source = source.replace(before, replacement)


insert("struct Lifetimes {", "var readback_counts: i64[10];\nstruct Lifetimes {")
insert("    // Every global container at one depth", "    readback_counts[0] += 1;\n    // Every global container at one depth")
insert("        let global = root.symbol >= 0", "        readback_counts[5] += 1;\n        let global = root.symbol >= 0")
insert("        let end = l.scratch.len;\n        for item in start..end {",
       "        let end = l.scratch.len; readback_counts[6] += end - start;\n        for item in start..end {")
insert("    let count = l.scratch.len - start;",
       "    let count = l.scratch.len - start; readback_counts[7] += 1; readback_counts[8] += count; if count == 1 { readback_counts[9] += 1; }")
insert("    if p.diagnostics.len == 0 { life_export_provenance",
       '    print("readback_counts ", readback_counts);\n    if p.diagnostics.len == 0 { life_export_provenance')

if args.mode != "baseline":
    insert("            contents = root.contents;", "            readback_counts[1] += 1; contents = root.contents;")
    insert("    var slot: i64 = -1; var contents: i64 = -1;",
           "    var shadow: i64 = -1; var slot: i64 = -1; var contents: i64 = -1;")
    action = "return hit.result;"
    if args.mode == "shadow":
        action = "shadow = hit.result;"
    insert("{ return hit.result; }", "{ readback_counts[2] += 1; " + action + " }")
    insert("    if slot >= 0 {\n        // Grow on repeated misses.",
           """    if shadow >= 0 {
        if shadow != set { readback_counts[4] += 1; }
        return set;
    }
    if slot >= 0 {
        // Grow on repeated misses.""")
    insert("    if p.diagnostics.len == 0 { life_export_provenance",
           '    print("slots ", l.local_reads.len);\n    if p.diagnostics.len == 0 { life_export_provenance')
path.write_text(source)

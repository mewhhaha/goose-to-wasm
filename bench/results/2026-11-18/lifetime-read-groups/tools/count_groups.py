"""Instrument either replay trial in a separate compiler source checkout."""
from pathlib import Path
import sys

path = Path(sys.argv[1]) / "selfhost/checker_lifetimes.goose"
source = path.read_text()

def replace(old, new):
    global source
    if source.count(old) != 1:
        raise ValueError(f"expected one occurrence of {old!r}")
    source = source.replace(old, new)

replace("fn life_replay_group(", "var group_counts: i64[10];\nfn life_replay_group(")
marker = "    let version = l.frames[frame].reads_version;\n"
if "changed_read_version" in source:
    marker = marker.replace("reads_version", "changed_read_version")
replace(marker, "    group_counts[0]++;\n" + marker)
replace("if at < 0 || (l.summary_reads[last].before as i64) < at { return",
        "if at < 0 || (l.summary_reads[last].before as i64) < at { group_counts[1]++; return")
replace("    var read = first; var count:", """    if group.first as i64 != first { group_counts[2]++; }
    else if group.chain != chain { group_counts[3]++; }
    else if group.version != version { group_counts[4]++; }
    else { group_counts[5]++; }
    var read = first; var count:""")
replace("        count++;\n        if life_leaf_offered", "        count++; group_counts[6]++;\n        if life_leaf_offered")
replace("        l.offer_count = 0; l.offer_recursive = false;\n        life_construct_read(p, l, l.leaves",
        "        group_counts[7]++; l.offer_count = 0; l.offer_recursive = false;\n        life_construct_read(p, l, l.leaves")
replace("    if count == 8 && offered", "    if count == 8 { group_counts[8]++; }\n    if count == 8 && offered")
replace("        l.read_groups[slot] = LifeReadGroup", "        group_counts[9]++; l.read_groups[slot] = LifeReadGroup")
marker = "    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }"
report = '\n    print("GROUP_COUNTS ", group_counts);'
if "read_group_count" in source:
    report += '\n    print("GROUP_TABLE ", l.read_group_count, " ", l.read_groups.len);'
replace(marker, marker + report)
path.write_text(source)

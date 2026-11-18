"""On top of instrument.py, count uninterrupted runs of per-entry construct-read stamp hits."""
from pathlib import Path
import sys
p=Path(sys.argv[1])/'selfhost/checker_lifetimes.goose'
s=p.read_text()
def rep(a,b,count):
 global s
 assert s.count(a)==count,(a,s.count(a),count)
 s=s.replace(a,b)
rep("fn lp_apply(", """var lp_run: i64[2]; var lp_hist_runs: i64[14]; var lp_hist_items: i64[14];
fn lp_flush(phase: i64) {
    let n = lp_run[phase]; if n == 0 { return; }
    var bucket: i64 = 0; var minimum: i64 = 1;
    while bucket < 6 && n >= 2*minimum { minimum *= 2; bucket++; }
    lp_hist_runs[phase*7+bucket]++; lp_hist_items[phase*7+bucket] += n; lp_run[phase] = 0;
}
fn lp_apply(""",1)
rep('        print("REPLAY_CALLS ','''        for bucket in 0..7 { print("READ_STAMP_RUN ", phase, " ", bucket, " ", lp_hist_runs[phase*7+bucket], " ", lp_hist_items[phase*7+bucket]); }
        print("REPLAY_CALLS ''',1)
rep("    lp_applied[k]++;", "    lp_flush(k / 10); lp_applied[k]++;",1)
rep("lp_leaf[k]++;","lp_run[phase]++; lp_leaf[k]++;",5)
rep("lp_summary[k]++;","if k%10 == 3 { lp_run[phase]++; } else { lp_flush(phase); } lp_summary[k]++;",2)
rep("lp_filtered[k]++;","lp_flush(phase); lp_filtered[k]++;",1)
rep("    lp_depth--;","    lp_flush(phase); lp_depth--;",1)
p.write_text(s)

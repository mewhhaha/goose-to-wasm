"""Reproduce the frozen pass-three prediction from the released event trace."""

from collections import Counter, defaultdict
import gzip
import json
from pathlib import Path


def closure(frames, callers):
    marked = set(frames)
    queue = list(frames)
    while queue:
        for caller in callers[queue.pop()]:
            if caller not in marked:
                marked.add(caller)
                queue.append(caller)
    return marked


def main():
    directory = Path(__file__).resolve().parents[1]
    versions = Counter()
    reads = {}
    callers = defaultdict(set)
    writers = Counter()
    bodies = set()
    with gzip.open(directory / "calls.jsonl.gz", "rt") as trace:
        for line in trace:
            event, stage, *args = json.loads(line)
            if stage > 3:
                break
            if event == 2:
                executor, owner, kind, entry, _ = args
                versions["summary", owner] += 1
                if kind == 4:
                    versions["store", entry] += 1
                if stage == 3:
                    writers[executor] += 1
            elif event == 3:
                _, owner = args
                versions["result", owner] += 1
            elif stage == 2 and event == 4:
                caller, _, _, callee = args
                callers[callee].add(caller)
            elif stage == 2 and event in (5, 6, 7):
                caller, context, site, callee, *extra = args
                keys = []
                if event == 5:
                    keys.append(("result", callee))
                    if extra[0] == 0:
                        keys.append(("summary", callee))
                elif event == 6:
                    keys.append(("summary", callee))
                else:
                    keys.append(("store", extra[0]))
                for key in keys:
                    reads.setdefault((caller, context, site, callee, key), versions[key])
            elif stage == 2 and event == 9:
                direct = {caller for (caller, _, _, _, key), value in reads.items() if value != versions[key]}
                predicted = closure(direct, callers)
            elif stage == 3 and event == 5 and args[-1] == 0:
                bodies.add(args[3])
    for label, chosen in [("Direct readers", direct), ("Readers and their callers", predicted)]:
        missed = sum(count for frame, count in writers.items() if frame not in chosen)
        print(f"{label}: {len(chosen & bodies)} of {len(bodies)} bodies, {missed} of {sum(writers.values())} writes outside the prediction")


if __name__ == "__main__":
    main()

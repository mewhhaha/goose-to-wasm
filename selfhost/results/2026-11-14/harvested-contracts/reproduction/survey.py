#!/usr/bin/env python3
"""Survey the captured C++-era test programs against plain upstream.

Writes db.json: per unique source, its modules, compile flags, duplicate
fixtures, host imports and upstream run/check results at -O0/-O1/-O2."""
import hashlib, json, pathlib, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
U = "/home/jacobt/src/blot2/build/goose-port/upstream-32a4f44/build-upstream/goose"
US = "/home/jacobt/src/blot2/build/goose-port/upstream-32a4f44/source-upstream/stdlib"
CAP = HERE / "cap"


def run(cmd, cwd):
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=60, stdin=subprocess.DEVNULL, cwd=cwd)
        return {"exit": r.returncode, "stdout": r.stdout.decode(errors="replace"),
                "stderr": r.stderr.decode(errors="replace")}
    except subprocess.TimeoutExpired:
        return {"exit": "timeout", "stdout": "", "stderr": ""}


def main():
    fixtures = {}
    for path in (ROOT / "tests/fixtures").rglob("*"):
        if path.is_file():
            fixtures.setdefault(hashlib.sha256(path.read_bytes()).hexdigest(), str(path.relative_to(ROOT)))
    programs = {}
    for module in sorted(p for p in CAP.iterdir() if p.is_dir()):
        flags = {}
        cmds = module / "cmds.txt"
        if cmds.exists():
            for line in cmds.read_text().splitlines():
                h, rest = line.split(" ", 1)
                flags.setdefault(h, set()).update(w for w in rest.split() if w.startswith("--") or w.startswith("-O"))
        for f in sorted(module.glob("*.goose")):
            data = f.read_bytes()
            key = hashlib.sha256(data).hexdigest()
            entry = programs.setdefault(key, {"hash": f.stem, "sha256": key, "modules": [], "flags": set(),
                                              "text": data.decode()})
            entry["modules"].append(module.name)
            entry["flags"] |= flags.get(f.stem, set())
    work = pathlib.Path(HERE / "work")
    work.mkdir(exist_ok=True)

    def survey(entry):
        d = work / entry["hash"]
        d.mkdir(exist_ok=True)
        src = d / "prog.goose"
        src.write_text(entry["text"])
        text = entry["text"]
        entry["fixture_duplicate"] = fixtures.get(entry["sha256"])
        entry["externs"] = re.findall(r"\bextern\s+fn\s+(\w+)", text)
        entry["exports"] = re.findall(r"\bexport\s+fn\s+(\w+)", text)
        entry["upstream"] = {}
        for level in (0, 1, 2):
            entry["upstream"][f"O{level}"] = run([U, "run", str(src), "--stdlib", US, f"-O{level}"], d)
        entry["upstream"]["check"] = run([U, "check", str(src), "--stdlib", US], d)
        entry["flags"] = sorted(entry["flags"])
        return entry

    with ThreadPoolExecutor(12) as pool:
        rows = list(pool.map(survey, programs.values()))
    (HERE / "db.json").write_text(json.dumps(rows, indent=1) + "\n")
    print(len(rows), "unique programs")


if __name__ == "__main__":
    main()

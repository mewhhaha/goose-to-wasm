"""Run from the repository root: python controls.py BASELINE ISOLATED COMBINED OUT.json."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    baseline, isolated, combined, out = sys.argv[1:]
    compilers = {"baseline": Path(baseline), "isolated": Path(isolated), "combined": Path(combined)}
    kernel = Path(__file__).with_name("sum.goose").resolve()
    alias = Path("tests/fixtures/varint_cursor_alias.goose")
    sources = sorted(Path("examples").glob("*.goose"))
    sources += [Path("bench/langbench/mandelbrot.goose"), Path("tests/fixtures/varint_grow_loops.goose"), alias, kernel]
    rows = []
    with tempfile.TemporaryDirectory() as directory:
        for source in sources:
            for width in (32, 64):
                args = ["--stdlib", "stdlib", "--target", "wasm-direct", "-O2", "--wasm-max-pages", "8192"]
                if width == 64:
                    args.append("--wasm-memory64")
                modules = {}
                for label, compiler in compilers.items():
                    target = Path(directory) / (label + ".wasm")
                    subprocess.run([compiler, source, *args, "-o", target], check=True)
                    modules[label] = sha(target)
                if modules["isolated"] != modules["combined"]:
                    raise ValueError(f"combined compiler differs on {source} wasm{width}")
                if source == kernel:
                    if modules["baseline"] == modules["isolated"]:
                        raise ValueError("missing varint lowering change")
                    value = subprocess.check_output(["node", "scripts/run_wasm.mjs", target], input=b"8008\n").split()
                    if len(value) != 2 or int(value[0]) != -24579:
                        raise ValueError(f"wrong combined compiler result {value}")
                elif modules["baseline"] != modules["isolated"]:
                    raise ValueError(f"changed control {source} wasm{width}")
                if source == alias:
                    value = subprocess.check_output(["node", "scripts/run_wasm.mjs", target])
                    if value != b"7\n":
                        raise ValueError(f"wrong local-alias result {value}")
                rows.append({"source": str(source.relative_to(Path.cwd()) if source.is_absolute() else source),
                             "source_sha256": sha(source), "width": width, "modules": modules})
    Path(out).write_text(json.dumps({"compilers": {name: sha(p) for name, p in compilers.items()},
                                     "rows": rows}, indent=2) + "\n")


if __name__ == "__main__":
    main()

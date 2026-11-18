"""Check, parse, or emit a frozen Goose project with the experimental memory32 compiler."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import os
from pathlib import Path
import shutil
import sys
import tempfile
import threading

import wasmtime

from recovery import Partition, compile_with_recovery, read_layout, save_layout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "compiler", type=Path, help="adapter.wasm built by build_probe.py"
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("--stdlib", type=Path, required=True)
    parser.add_argument(
        "--mode",
        choices=("check", "parse", "emit"),
        default="check",
        help="emit writes a memory64 Wasm module to standard output",
    )
    parser.add_argument(
        "--repo", type=Path, default=Path(__file__).resolve().parents[4]
    )
    parser.add_argument(
        "--layout-cache",
        type=Path,
        help="directory for a successful layout, keyed by compiler SHA-256",
    )
    parser.add_argument("--verbose", action="store_true")
    a = parser.parse_args()
    sys.path.insert(0, str(a.repo.resolve() / "scripts"))
    from run_wasmtime import (
        create_engine,
        create_hosted_config,
        HOSTED_STACK_BYTES,
        PreparedModule,
    )

    data = a.compiler.read_bytes()
    config = create_hosted_config()
    config.cache = True
    engine = create_engine(config)
    module = wasmtime.Module(engine, data)
    exports = {e.name for e in module.exports}
    if (
        not {
            "trial.failed_limit",
            "trial.request_bytes",
            "goose.region_table",
            "goose.region_count",
        }
        <= exports
    ):
        parser.error("the supplied compiler lacks the memory32 recovery exports")
    digest = hashlib.sha256(data).hexdigest()
    prepared = PreparedModule(engine, module, digest, None, {})
    threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
    saved = read_layout(a.layout_cache, digest)
    partition = Partition(4, saved)
    with tempfile.TemporaryDirectory() as temp, ThreadPoolExecutor(1) as worker:
        output = Path(temp) / "output.wasm"
        args = ["compiler", os.fspath(a.source), "--stdlib", os.fspath(a.stdlib)]
        if a.mode == "emit":
            args += [
                "--target",
                "wasm-direct",
                "-O2",
                "--wasm-memory64",
                "--wasm-max-pages",
                "262144",
                "-o",
                str(output),
            ]
        else:
            args.append("--" + a.mode)
        result, times = worker.submit(
            compile_with_recovery, data, prepared, args, partition, output
        ).result()
        if a.verbose:
            for miss in partition.failures:
                print(
                    f"region {miss['region']} held {miss['used']} of {miss['capacity']} bytes "
                    f"and requested {miss['request']} more",
                    file=sys.stderr,
                )
            print(
                f"{len(times)} attempt(s), {sum(times) / 1e9:.3f} guest seconds",
                file=sys.stderr,
            )
        if result["exit_code"] == 0 and a.layout_cache and partition.bounds != saved:
            save_layout(a.layout_cache, digest, partition.bounds)
        sys.stderr.write(result["stderr"])
        if result["exit_code"] == 0 and a.mode == "emit":
            with output.open("rb") as stream:
                shutil.copyfileobj(stream, sys.stdout.buffer)
        else:
            sys.stdout.buffer.write(result["stdout"])
        return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())

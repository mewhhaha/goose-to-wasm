"""Compare native and cold/resident Wasmtime self-emission using a frozen compiler stage."""

from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from importlib.metadata import version
from pathlib import Path
import json
import os
import resource
import shutil
import subprocess
import sys
import threading
import time

repo, stage, dest = [Path(a).resolve() for a in sys.argv[1:4]]
sys.path.insert(0, str(repo / "bench"))
sys.path.insert(0, str(repo / "scripts"))
from selfhost_comparison import SOURCE, WASM_FLAGS, identity, verify_frozen_source

project = dest / "self-project"
output = dest / "output.wasm"
wasm = stage / "build-1/compiler.wasm"
native = stage / "build-1/compiler-native"
args = [*SOURCE, *WASM_FLAGS, "-o", str(output)]
clock = time.monotonic_ns


def worker():
    import wasmtime
    from run_wasmtime import (
        create_engine,
        create_hosted_config,
        HOSTED_STACK_BYTES,
        PreparedModule,
        run_module,
    )

    data = wasm.read_bytes()
    config = create_hosted_config()
    config.parallel_compilation = False
    engine = create_engine(config)
    module = wasmtime.Module(engine, data)
    prepared = PreparedModule(engine, module, sha256(data).hexdigest(), None, {})
    threading.stack_size(HOSTED_STACK_BYTES + (64 << 20))
    os.chdir(project)
    with ThreadPoolExecutor(1) as pool:
        for _ in sys.stdin:
            result = pool.submit(
                run_module, data, b"", prepared=prepared, arguments=["compiler", *args]
            ).result()
            if result["exit_code"] or result["stderr"] or result["stdout"]:
                raise ValueError(
                    (result["exit_code"], result["stderr"], result["stdout"])
                )
            print("ok", flush=True)


def measure():
    os.sched_setaffinity(0, {7})
    resource.setrlimit(
        resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1])
    )
    dest.mkdir(exist_ok=True, parents=True)
    manifest = json.loads((stage / "builds.json").read_text())
    verify_frozen_source(
        stage / "source", manifest["source_commit"], manifest["source_archive_sha256"]
    )
    shutil.copytree(stage / "source", project)
    driver = project / "selfhost/driver.goose"
    original = driver.read_bytes()
    old_text = b"Usage: goose-selfhost"
    assert original.count(old_text) == 1
    new_text = b"Usage: goose-compiler"
    changed = original.replace(old_text, new_text)
    pins = {
        "compiler": manifest["source_commit"],
        "source_archive_sha256": manifest["source_archive_sha256"],
        "native": identity(native),
        "wasm": identity(wasm),
        "host": identity(repo / "scripts/run_wasmtime.py"),
        "wasmtime": version("wasmtime"),
        "cpu": 7,
        "variant": "default memory64",
        "before": old_text.decode(),
        "after": new_text.decode(),
    }
    samples = []
    outputs = {}
    for i in range(3):
        for mode, text in [("fresh", original), ("edited", changed)]:
            driver.write_bytes(text)
            output.unlink(missing_ok=True)
            start = clock()
            subprocess.run([native, *args], cwd=project, check=True)
            elapsed = clock() - start
            digest = identity(output)
            if mode in outputs:
                assert outputs[mode] == digest
            outputs[mode] = digest
            samples.append(dict(round=i + 1, host="native", mode=mode, ns=elapsed))
        assert (
            outputs["fresh"] == identity(wasm) and outputs["fresh"] != outputs["edited"]
        )
        driver.write_bytes(original)
        output.unlink(missing_ok=True)
        start = clock()
        with subprocess.Popen(
            [
                sys.executable,
                str(Path(__file__).resolve()),
                repo,
                stage,
                dest,
                "worker",
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        ) as child:
            try:
                for mode, text in [
                    ("cold", original),
                    ("hot", original),
                    ("edited", changed),
                ]:
                    if mode != "cold":
                        if mode == "edited":
                            driver.write_bytes(text)
                        output.unlink()
                        start = clock()
                    child.stdin.write("emit\n")
                    child.stdin.flush()
                    ack = child.stdout.readline()
                    elapsed = clock() - start
                    assert ack == "ok\n", ack
                    expected = outputs["fresh"]
                    if mode == "edited":
                        expected = outputs["edited"]
                    assert identity(output) == expected
                    samples.append(
                        dict(round=i + 1, host="wasmtime", mode=mode, ns=elapsed)
                    )
                    print(i + 1, mode, round(elapsed / 1e9, 3), flush=True)
            finally:
                child.stdin.close()
            assert child.wait() == 0
        driver.write_bytes(original)
        (dest / "self-emit.json").write_text(
            json.dumps(dict(pins=pins, outputs=outputs, samples=samples), indent=2)
            + "\n"
        )


if __name__ == "__main__":
    if sys.argv[4:] == ["worker"]:
        worker()
    else:
        measure()

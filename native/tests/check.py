#!/usr/bin/env python3
"""Run pristine runtime contracts as direct headers and standalone C."""

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import subprocess
import time


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("native_pack", HERE.parent / "pack.py")
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)
FLAGS = ["-O2", "-std=gnu11", "-pthread"]
LIBS = ["-lm", "-ldl"]
SMOKE = """
int main(int argc, char **argv) {
    gs_rt_init(argc, argv, 1, 1, 0);
    gs_rhdr value = { GS(0)->top, 0 };
    gs_rref out = { &value, GS(0) };
    gs_bld_append(out, "runtime glue ok\\n", 16);
    sl_u8 bytes = { value.base, value.len };
    gs_os_write_stdout(bytes);
    gs_release_regions();
    free(gs_stks);
    return 0;
}
"""


def sha(content):
    return hashlib.sha256(content).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="scratch builds and evidence directory")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    compiler = shlex.split(os.environ.get("CC", "cc"))
    executable = Path(shutil.which(compiler[0])).resolve()
    sections = PACK.runtime_sections()
    assert sections == PACK.runtime_sections(), "runtime sections are not deterministic"
    for section in (*sections, "standalone", "object"):
        assert PACK.runtime_text(section) == PACK.runtime_text(section)
    manifest = json.loads((HERE / "source-manifest.json").read_text())
    report = {
        "collected_at_utc": datetime.now(timezone.utc).isoformat(),
        "host": platform.uname()._asdict(),
        "measurement": "Wall time and wait4 resource usage per child; peak RSS includes process launch setup.",
        "pack_sha256": sha((HERE.parent / "pack.py").read_bytes()),
        "driver_sha256": sha(Path(__file__).read_bytes()),
        "runtime": json.loads((PACK.RUNTIME / "manifest.json").read_text()),
        "fixtures": manifest,
        "compiler": {
            "command": compiler,
            "path": str(executable),
            "sha256": sha(executable.read_bytes()),
            "version": subprocess.check_output([*compiler, "--version"], text=True),
            "target": subprocess.check_output([*compiler, "-dumpmachine"], text=True).strip(),
        },
        "sections_sha256": {name: sha(PACK.runtime_text(name).encode()) for name in (*sections, "standalone", "object")},
        "runs": [],
    }

    def run(name, command, expected=None):
        stdout_path = output / (name + ".stdout")
        stderr_path = output / (name + ".stderr")
        started = time.monotonic()
        with stdout_path.open("w") as stdout, stderr_path.open("w") as stderr:
            process = subprocess.Popen(list(map(str, command)), stdout=stdout, stderr=stderr)
            _, status, usage = os.wait4(process.pid, 0)
            process.returncode = os.waitstatus_to_exitcode(status)
        elapsed = time.monotonic() - started
        row = {"name": name, "command": list(map(str, command)), "elapsed_seconds": elapsed, "user_seconds": usage.ru_utime, "system_seconds": usage.ru_stime, "max_rss_kib": usage.ru_maxrss, "returncode": process.returncode}
        report["runs"].append(row)
        (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        if process.returncode:
            raise RuntimeError(f"{name} failed: {stderr_path.read_text()}")
        if expected is not None and stdout_path.read_text() != expected:
            raise RuntimeError(f"{name}: unexpected stdout {stdout_path.read_text()!r}")
        print(f"{name}: ok ({elapsed:.3f}s, {usage.ru_maxrss} KiB)", flush=True)

    for name, identity in manifest["files"].items():
        source = (HERE / name).read_bytes()
        assert sha(source) == identity["sha256"], f"fixture changed: {name}"
        restored = source.replace(b'../runtime/', b'../../src/runtime/')
        assert sha(restored) == identity["upstream_sha256"], f"fixture contract differs: {name}"
        expected = "runtime thread cleanup ok\n"
        if name == "runtime_trim_memory.c":
            expected = "runtime trim memory ok\n"
        for mode in ("direct", "amalgamated"):
            stem = Path(name).stem + "-" + mode
            path = HERE / name
            if mode == "amalgamated":
                text = source.decode()
                for header in ("runtime.h", "runtime_impl.h", "runtime_threads.h"):
                    text = text.replace(f'#include "../runtime/{header}"', PACK.verified_files()[header])
                path = output / (stem + ".c")
                path.write_text(text)
            report.setdefault("inputs_sha256", {})[stem] = sha(path.read_bytes())
            binary = output / stem
            run(stem + "-compile", [*compiler, *FLAGS, path, *LIBS, "-o", binary])
            run(stem + "-run", [binary], expected)

    standalone = output / "glue-standalone.c"
    standalone.write_text(PACK.runtime_text() + SMOKE)
    binary = output / "glue-standalone"
    run("glue-standalone-compile", [*compiler, *FLAGS, standalone, *LIBS, "-o", binary])
    run("glue-standalone-run", [binary], "runtime glue ok\n")
    runtime = output / "runtime-object.c"
    runtime.write_text(PACK.runtime_text("object"))
    obj = output / "runtime.o"
    run("runtime-object-compile", [*compiler, *FLAGS, "-c", runtime, "-o", obj])
    program = output / "glue-linked.c"
    program.write_text("#define GS_SEPARATE_RUNTIME 1\n#define GS_NEED_THREADS 1\n" + sections["header"] + PACK.CORE_TYPES + PACK.verified_files()["runtime_ext.h"] + SMOKE)
    binary = output / "glue-linked"
    run("glue-linked-compile", [*compiler, *FLAGS, program, obj, *LIBS, "-o", binary])
    run("glue-linked-run", [binary], "runtime glue ok\n")
    adapter = HERE / "threads_adapter.c"
    report["inputs_sha256"][adapter.name] = sha(adapter.read_bytes())
    report["inputs_sha256"]["threads.h"] = sha((HERE.parent / "threads.h").read_bytes())
    for mode, options in (("release", ["-O2"]), ("sanitized", ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"])):
        binary = output / ("threads-adapter-" + mode)
        run("threads-adapter-" + mode + "-compile", [*compiler, "-std=gnu11", "-pthread", *options, adapter, *LIBS, "-o", binary])
        run("threads-adapter-" + mode + "-run", [binary], "native thread adapters ok\n")
    for header in ("storage.h", "pools.h", "relative.h", "images.h", "runs.h"):
        report["inputs_sha256"][header] = sha((HERE.parent / header).read_bytes())
    for stem, expected in (("fixed_values", "native fixed values ok\n"), ("pools", "native pools ok\n"), ("relative", "native relative cells ok\n"), ("var_relative", "bounded varint relative cells ok\n"), ("bounded_cells", "bounded physical relative cursor bytes ok\n"), ("image_storage", "native image storage ok\n"), ("runs", "native bounded run receivers ok\n"), ("lazy_regions", "native lazy regions ok\n")):
        fixture = HERE / (stem + ".c")
        report["inputs_sha256"][fixture.name] = sha(fixture.read_bytes())
        for mode, options in (("release", ["-O2"]), ("sanitized", ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"])):
            name = stem.replace("_", "-") + "-" + mode
            binary = output / name
            run(name + "-compile", [*compiler, "-std=gnu11", "-pthread", *options, fixture, *LIBS, "-o", binary])
            run(name + "-run", [binary], expected)
            if stem in ("bounded_cells", "runs"):
                errors = (output / (name + "-run.stderr")).read_text()
                expected_errors = 7
                if stem == "runs":
                    expected_errors = 10
                assert errors.count("goose runtime error:") == expected_errors, errors
                assert "AddressSanitizer" not in errors, errors
                assert "runtime error:" not in errors.replace("goose runtime error:", ""), errors
    for path in (standalone, runtime, program):
        report["inputs_sha256"][path.name] = sha(path.read_bytes())
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()

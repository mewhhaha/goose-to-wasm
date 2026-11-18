"""Build a recovery-aware emitter, then use it on unchanged compiler sources."""

from pathlib import Path
import resource
import shutil
import subprocess
import sys

repo, stage, profile, out = (Path(a).resolve() for a in sys.argv[1:])
resource.setrlimit(
    resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1])
)
src = stage / "source"
out.mkdir(exist_ok=True, parents=True)
tree = out / "probe"
shutil.copytree(src / "selfhost", tree / "selfhost", dirs_exist_ok=True)
for name in ("stdlib", "native"):
    if not (tree / name).exists():
        (tree / name).symlink_to(src / name)
path = tree / "selfhost/codegen.goose"
code = path.read_text()


def replace(old, new):
    global code
    assert code.count(old) == 1, old
    code = code.replace(old, new)


# The two added globals exist only in memory32 region modules emitted by the probe.
replace(
    "if m.pool_global >= 0 { count += 1; } wb_u(out, count);",
    """if m.pool_global >= 0 { count += 1; }
    var exported_count = count;
    if m.regions_enabled && !cg_wide { exported_count += 2; }
    wb_u(out, exported_count);""",
)
replace(
    "    }\n}\n// Linear memory above the static data",
    """    }
    if m.regions_enabled && !cg_wide {
        wb_byte(out, 0x7f); wb_byte(out, 1); wb_i32(out, 0); wb_byte(out, 0x0b);
        wb_byte(out, 0x7e); wb_byte(out, 1); wb_i64(out, 0); wb_byte(out, 0x0b);
    }
}
// Linear memory above the static data""",
)
replace(
    "&& !m.scalar && cg_region_stats;", "&& !m.scalar && (cg_region_stats || !cg_wide);"
)
replace(
    "if region_words { export_count += 2; }",
    "if region_words { export_count += 2; if !cg_wide { export_count += 2; } }",
)
replace(
    'if region_words { wb_export(section, "goose.region_table", 3, 9); wb_export(section, "goose.region_count", 3, 8); }',
    """if region_words {
        wb_export(section, "goose.region_table", 3, 9); wb_export(section, "goose.region_count", 3, 8);
        if !cg_wide {
            var index = 12; if m.pool_global >= 0 { index++; }
            wb_export(section, "trial.failed_limit", 3, index); wb_export(section, "trial.request_bytes", 3, index + 1);
        }
    }""",
)
replace(
    'cg_get(f, bytes); cg_get(f, limit); cg_get(f, cursor); wa_op(f.code, 0x6b); wa_extend(f.code); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted");',
    """cg_get(f, bytes); cg_get(f, limit); cg_get(f, cursor); wa_op(f.code, 0x6b); wa_extend(f.code); wb_byte(f.code, 0x56);
    cg_begin(f, 0x04, 0x40);
    if !cg_wide {
        var index = 12; if m.pool_global >= 0 { index++; }
        cg_get(f, limit); wb_op(f.code, 0x24, index); cg_get(f, bytes); wb_op(f.code, 0x24, index + 1);
    }
    cg_abort(p, m, f, node, "data region exhausted"); cg_end(f);""",
)
path.write_text(code)
opts = ["selfhost/main.goose", "--stdlib", "stdlib", "--target", "wasm-direct", "-O2"]
emitter = out / "emitter.wasm"
subprocess.run(
    [
        stage / "build-1/compiler-native",
        *opts,
        "--wasm-memory64",
        "--wasm-max-pages",
        "262144",
        "-o",
        emitter,
    ],
    cwd=tree,
    check=True,
)
host = repo / "host/rust/target/release/goose-wasmtime"
subprocess.run(
    [
        host,
        emitter,
        "--cache",
        out / "emitter.cwasm",
        "--",
        *opts,
        "--wasm-max-pages",
        "65535",
        "--wasm-region-profile",
        profile,
        "-o",
        out / "adapter.wasm",
    ],
    cwd=src,
    check=True,
)

#!/usr/bin/env python3
"""Verified, deterministic plain-C runtime text; no upstream checkout needed."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys


RUNTIME = Path(__file__).resolve().parent / "runtime"
FILES = (
    "runtime.h", "runtime_impl.h", "runtime_threads.h",
    "runtime_ext.h", "runtime_os.h", "goose.h",
)
CORE_TYPES = """#pragma pack(push, 1)
typedef struct { uint8_t *base; int64_t len; } gs_rhdr;
typedef struct { gs_rhdr *hdr; gs_stack *stk; } gs_rref;
typedef struct { uint8_t *data; int64_t len; } sl_u8;
#pragma pack(pop)
"""


def verified_files():
    """Read only source-owned files, checking the vendored manifest first."""
    manifest = json.loads((RUNTIME / "manifest.json").read_text())
    data = {}
    for name, identity in manifest["files"].items():
        content = (RUNTIME / name).read_bytes()
        if hashlib.sha256(content).hexdigest() != identity["sha256"]:
            raise ValueError(f"runtime hash mismatch: {name}")
        data[name] = content.decode("utf-8")
    for name in FILES:
        if name not in data:
            raise ValueError(f"runtime manifest missing: {name}")
    return data


def runtime_sections():
    """Emit around generated types: header + body + types + glue.

    Header and body precede packed generated gs_rhdr, gs_rref and sl_u8.
    Glue follows them. The FFI header is for separate C sidecars only.
    System includes and preprocessor guards are preserved verbatim.
    """
    files = verified_files()

    def section(names):
        pieces = []
        for name in names:
            content = files[name]
            # Quoted includes are local; reject any unknown dependency.
            for local in re.findall(r'^\s*#\s*include\s*"([^"]+)"', content, re.M):
                if local not in FILES:
                    raise ValueError(f"unknown local runtime include: {local}")
            content = re.sub(r'^\s*#\s*include\s*"[^"]+"[^\n]*\n', '', content, flags=re.M)
            pieces.append(f"/* native/runtime/{name} */\n" + content)
        return "\n".join(pieces)

    return {
        "header": section(("runtime.h",)),
        "body": section(("runtime_impl.h", "runtime_threads.h")),
        "glue": section(("runtime_ext.h", "runtime_os.h")),
        "ffi_header": section(("goose.h",)),
    }


def runtime_text(section="standalone"):
    sections = runtime_sections()
    if section == "standalone":
        return sections["header"] + sections["body"] + CORE_TYPES + sections["glue"]
    if section == "object":
        options = "#define GS_RUNTIME_OBJECT 1\n#define GS_SEPARATE_RUNTIME 1\n#define GS_NEED_THREADS 1\n"
        return options + sections["header"] + sections["body"] + sections["glue"]
    return sections[section]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--section", choices=("header", "body", "glue", "ffi_header", "standalone", "object"), default="standalone")
    parser.add_argument("--output", type=Path, help="write UTF-8 C text here instead of stdout")
    args = parser.parse_args()
    content = runtime_text(args.section)
    if args.output:
        args.output.write_bytes(content.encode("utf-8"))
    else:
        sys.stdout.buffer.write(content.encode("utf-8"))


if __name__ == "__main__":
    main()

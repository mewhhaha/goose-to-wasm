#!/usr/bin/env bash
# Usage: bash run.sh REPO COMPILER_STAGE PROJECT_STAGE CONTROLS EXISTING_OR_NEW_OUTPUT
# The exact stage layout is documented in compiler-record-access/tools/modules.sh.
set -euo pipefail
tools_dir=$(dirname "$(realpath "$0")")
repo=$(realpath "$1")
compiler=$(realpath "$2")
project=$(realpath "$3")
controls=$(realpath "$4")
stage=$(realpath -m "$5")
mkdir -p "$stage"
python="$repo/.venv/bin/python"
"$python" "$tools_dir/train.py" "$repo" "$compiler" "$stage" --cpu 3
"$python" "$tools_dir/smooth.py" "$compiler" "$stage" --cpu 3
"$python" "$tools_dir/validate.py" "$repo" "$compiler" "$project" "$controls" "$stage" \
    --cpu 3 --rounds 4 --extra-case "root32=$stage/root32.wasm" --report validation-root.json
"$python" "$tools_dir/diagnose.py" "$repo" "$compiler" "$project" "$controls" "$stage" --cpu 3
"$python" "$tools_dir/summarize.py" "$stage"
"$python" "$tools_dir/two_project_fit.py" "$repo" "$compiler" "$project" "$controls" "$stage" --cpu 3

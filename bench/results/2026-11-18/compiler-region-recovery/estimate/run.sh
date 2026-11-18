#!/usr/bin/env bash
# Usage: bash run.sh REPO COMPILER_STAGE PROJECT_STAGE MEMORY_STAGE OUTPUT [CPU]
set -eu
tools_dir=$(dirname "$(realpath "$0")")
repo=$(realpath "$1")
compiler=$(realpath "$2")
project=$(realpath "$3")
memory=$(realpath "$4")
output=$(realpath -m "$5")
cpu=${6:-4}
export PYTHONDONTWRITEBYTECODE=1
"$repo/.venv/bin/python" "$tools_dir/measure_estimate.py" "$repo" "$compiler" "$project" "$memory" "$output" --cpu "$cpu"
"$repo/.venv/bin/python" "$tools_dir/shape_control.py" "$repo" "$compiler" "$memory" "$output" --cpu "$cpu"

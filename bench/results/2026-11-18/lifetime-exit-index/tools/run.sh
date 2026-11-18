#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

scratch=$PWD/build/lifetime-exit-index-2026-11-18/refresh-tools
prior=$PWD/bench/results/2026-11-18/wasm-copy-and-owner-reads
resident=$PWD/bench/results/2026-11-17/compiler-iteration/langbench-hot.json
out=${2:-$scratch/result}
tool=${1:-all}
cpu=1
export PATH=/home/jacobt/.local/share/fnm/node-versions/v24.22.1/installation/bin:$PWD/.venv/bin:/usr/bin:/bin
unset NODE_OPTIONS LD_PRELOAD LD_LIBRARY_PATH
export MPLBACKEND=Agg
export MPLCONFIGDIR="$scratch/plot-cache"
py=$PWD/.venv/bin/python
qualification=$PWD/build/lifetime-exit-index-2026-11-18/qualification
candidate=$qualification/bootstrap/bin/goose
bootstrap_receipt=$qualification/bootstrap/bootstrap/report.json
parent=$PWD/build/wasm-copy-2026-11-18/selfhost-chart/emitter
parent_source=$PWD/build/wasm-copy-2026-11-18/selfhost-chart/source
parent_commit=f89ecf30aea76003e4536bcf6fa8f280efb287cc
source_commit=ba9dece0d4e58abb22c815dae1f37e28c99758de
frozen=$scratch/source
host=$PWD/build/perf-2026-11-17-followup/host-tools/goose-wasmtime
upstream=$PWD/build/langbench-native/goose
upstream_stdlib=$PWD/build/langbench-goose-source/stdlib
label="Ryzen 7 3800X · CPU $cpu"

prepare() {
    mkdir -p "$out"
    if [[ ! -d "$frozen" ]]; then
        mkdir "$frozen"
        local modules
        mapfile -t modules < <(git ls-tree --name-only "$source_commit:selfhost" | sed -n '/\.goose$/s#^#selfhost/#p')
        git archive "$source_commit" "${modules[@]}" stdlib native | tar -x -C "$frozen"
    fi
    sha256sum -c <<EOF
18b8113e3fc91d038882cdad8ab4b2e98971474f285f2dacc6756c047ceeb14d  $parent
999d9ce25ead118af32cc859ed7bc1b0bac41521c331fab44d0d16d65600023b  $host
c8cab78ded8e97347471621566f986a954a8d2caffdc38c7fab9262efecaf300  $host-aot
9e4d9ff8927c69c653031850f1b0911ce6827dc71648f1e11448ed06736b75e0  $upstream
EOF
    "$py" "$scratch/verify.py" pins "$prior" "$source_commit" "$frozen" "$parent_source" "$out/pins.json" "$parent_commit" "$cpu" "$candidate" "$bootstrap_receipt"
}

catalog() {
    "$py" bench/compare_compilers.py --parent "$parent" --parent-source "$parent_source/selfhost" \
        --parent-label "${parent_commit:0:7}" --candidate "$candidate" --candidate-source "$frozen/selfhost" \
        --candidate-label 'Current Goose' --stdlib "$frozen/stdlib" --samples 31 \
        --cpu "$cpu" --seed 111757 --timeout 120 --cc gcc --node node --output-dir "$out/compiler-catalog"
    cp "$out/compiler-catalog/report.json" "$out/compiler-comparison.json"
}

examples() {
    taskset -c "$cpu" "$py" bench/examples.py --goose "$candidate" --cc gcc --node node \
        --machine-label "$label" --compile-samples 5 --samples 5 --warmups 1 --seed 111758 \
        --backends direct native --output-dir "$out/examples"
    cp "$out/examples/report.json" "$out/examples.json"
}

hosts() {
    taskset -c "$cpu" "$py" bench/wasmtime_host.py --host "$host" --aot-host "$host-aot" \
        --example-report "$out/examples/report.json" --machine-label "$label" \
        --samples 5 --prepare-samples 5 --warmups 1 --output-dir "$out/host"
    cp "$out/host/report.json" "$out/host.json"
}

langbench() {
    "$py" bench/langbench.py --profiles small medium official --samples 1 --compile-samples 5 \
        --cpu "$cpu" --seed 111758 --goose "$candidate" --stdlib "$PWD/stdlib" \
        --upstream-goose "$upstream" --upstream-stdlib "$upstream_stdlib" --output-dir "$out/langbench-build"
    cp "$out/langbench-build/report.json" "$out/langbench-build.json"
    "$py" "$scratch/verify.py" artifacts "$prior" "$resident" "$out/langbench-build.json" "$out/langbench-artifacts.json"
}

charts() {
    local reports=${3:-$out}
    mkdir -p "$out/charts"
    "$py" bench/compiler_comparison_charts.py "$reports/compiler-comparison.json" --output-dir "$out/charts" \
        --receipt "$out/compiler-chart.json"
    "$py" bench/example_charts.py "$reports/examples.json" --output-dir "$out/example-charts"
    "$py" bench/example_runtime_charts.py "$reports/host.json" --output-dir "$out/runtime-charts"
    "$py" bench/wasmtime_host_charts.py "$reports/host.json" --output-dir "$out/host-charts"
    "$py" bench/langbench_charts.py "$reports/langbench-build.json" --output-dir "$out/langbench-charts" \
        --receipt "$out/langbench-build-chart.json"
    cp "$out/example-charts/examples-compilation.svg" "$out/charts/goose-examples-compilation.svg"
    cp "$out/runtime-charts/examples-runtime.svg" "$out/charts/goose-examples-runtime.svg"
    cp "$out/host-charts/wasmtime-host-preparation.svg" "$out/charts/goose-host-preparation.svg"
    cp "$out/langbench-charts/langbench-compilation.svg" "$out/charts/"
    (cd "$out/charts" && sha256sum ./*.svg) > "$out/charts.sha256"
}

case "$tool" in
    all) prepare; catalog; langbench; examples; hosts ;;
    prepare|catalog|examples|hosts|langbench) "$tool" ;;
    charts) charts "$@" ;;
    *) exit 2 ;;
esac

# Examples

Ten programs exercise the supported Goose subset. Nine come from [Goose samples at revision `2e2bedef`](https://github.com/aardappel/goose/tree/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples); squares is local. They are examples, not performance benchmarks.

| Example | Focus | Adaptation |
| --- | --- | --- |
| [Squares](squares.goose) | Functions and loops | Local example |
| [Tour](tour.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/01_tour.goose) | Language tour | Explicit byte formatting and field updates |
| [Functions](functions.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/06_functions.goose) | Generics, higher-order functions, captures | Separate printed descriptions instead of string building |
| [Errors](errors.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/04_errors.goose) | Optionals, error flags, nonlocal returns | Explicit byte comparison and diagnostics bounded to 128 bytes |
| [Sieve](sieve.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/07_sieve.goose) | Primes and wrapping arithmetic | Removes timing; reduces input limit |
| [Sorting](sorting.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/09_sorting.goose) | Slices, searching, recursion | Removes timing; reduces inputs and compares slices elementwise |
| [Sudoku](sudoku.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/10_sudoku.goose) | Backtracking and bitmasks | Omits timing and sparse puzzle; replaces host popcount |
| [Maze](maze.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/11_maze.goose) | Breadth-first search and Dijkstra | Unchanged source and output |
| [VM](vm.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/19_vm.goose) | Enums, match dispatch, stack machine | Local decimal formatting |
| [Life](life.goose) · [upstream](https://github.com/aardappel/goose/blob/2e2bedef5b980bf013cac5aaa0095bfea64e5569/samples/20_life.goose) | Grid simulation and double buffering | Unchanged source and output |

The [manifest](manifest.json) records exact adaptations, upstream paths and hashes. Expected output is in [expected/](expected/). The examples use the repository’s [Apache-2.0 license](../LICENSE).

After [setup](../docs/GUIDE.md#quick-start-direct-compilation), run these commands from the repository root:

```sh
python scripts/goose_wasm.py build examples/maze.goose --backend direct --offline -O2 -o build/maze.wasm
node scripts/run_wasm.mjs build/maze.wasm
python scripts/run_wasmtime.py build/maze.wasm
```

Check all ten at O2 with direct Wasm on both engines:

```sh
python examples/run.py
```

Run the full native, C-to-Wasm and direct matrix at O0 and O2 (requires the oracle SDK):

```sh
python examples/run.py --backends native c-wasm direct --levels 0 2 --output-dir build/examples-qualification
```

The [retained qualification](../bench/results/2026-11-01/examples/qualification.json) records the results.

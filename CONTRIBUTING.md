# Contributing to Goose to Wasm

Thank you for your interest in contributing to `goose-to-wasm`!

## Development Workflow

1. **Plain upstream Goose is the language reference.** Keep `selfhost/main.goose` valid plain upstream C++ Goose whenever possible, and check compatibility against [docs/FEATURES.md](docs/FEATURES.md).
2. **Build and verify locally** (requires Python 3.11+, Clang or GCC, and Node or Wasmtime):

```sh
# Fast development build (8 parallel C units)
python3 scripts/bootstrap.py --build-dir build/dev --jobs 8

# Release-mode fixed-point bootstrap verification (reproduces checked-in seed/sources)
python3 scripts/bootstrap.py --verify
```

3. **Run tests before opening a PR:**

```sh
# Unit test suite
python3 -m unittest discover -s tests

# Full conformance suite against pinned contracts
python3 tests/conformance.py --compiler build/bin/goose --output-dir build/conformance \
  --levels 0 2 --known-gaps tests/conformance/known-gaps.json

# Full qualification gate (bootstrap + conformance + native checks + memory64 + unit tests)
python3 scripts/qualify.py --output-dir build/qualify --jobs 8
```

See [tests/README.md](tests/README.md) for qualification details and [selfhost/README.md](selfhost/README.md) for bootstrap and development build tips.

## Pull Requests & CI Approval

- **CI does not auto-run on pull requests.** For security and runner hygiene, GitHub Actions workflows on pull requests wait for maintainer approval before running. Once a maintainer reviews your diff and approves the run, the full qualification workflow will execute on the PR.
- Keep pull requests focused and include regression tests (or conformance contract coverage) for compiler, runtime, or host changes.
- Do not modify pinned benchmark results or conformance contracts without documenting the change and measurements per [AGENTS.md](AGENTS.md).
- Keep any local sibling checkouts (such as upstream Goose or `blot2`) strictly read-only.

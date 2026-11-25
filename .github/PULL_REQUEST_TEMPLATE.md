## Summary

<!-- Briefly describe what this pull request changes and why. -->

## Verification

- [ ] `python3 scripts/bootstrap.py --verify` (or `--build-dir build/dev --jobs 8`)
- [ ] `python3 -m unittest discover -s tests`
- [ ] `python3 tests/conformance.py --compiler build/bin/goosew --output-dir build/conformance --levels 0 2 --known-gaps tests/conformance/known-gaps.json`
- [ ] Updated docs / `docs/FEATURES.md` if behavior or compatibility changed

> **Note:** GitHub Actions CI does not run automatically on pull requests and will run after a maintainer approves the workflow.

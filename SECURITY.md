# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| `v2026.4-x` (latest release & `main`) | Yes |

## Reporting a Vulnerability

If you discover a security issue in `goose-to-wasm` (for example, a lifetime or bounds-checking soundness bug, a WebAssembly sandbox/memory-safety issue, or a host wrapper vulnerability), please report it privately via [GitHub Private Vulnerability Reporting](https://github.com/mewhhaha/goose-to-wasm/security/advisories/new) on this repository rather than opening a public issue.

Please include:
- A minimal `.goose` reproduction (or host invocation)
- Compiler version (`goosew --version`) and target flags
- Expected vs. observed behavior

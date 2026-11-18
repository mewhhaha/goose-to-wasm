# Project workflow

- Use plain upstream Goose as the language reference. Follow the [compatibility tracker](docs/FEATURES.md#blot2-compatibility) before tuning Blot2. Keep the sibling checkout read-only and measure frozen inputs.
- [Qualify changes](tests/README.md#qualifying-a-change). Measure compiler and runtime changes. Pin sources, tools, workloads and engines. Label separate reference runs and preserve rejected experiments. Keep README benchmark text and charts in step with the dated evidence.
- Push each batch to `origin/main` as soon as it qualifies and verify the remote commit.

# Why native Fibonacci was unusually fast

This follow-up separates the Goose frontend optimization level from the C compiler optimization level. It uses the existing runtime-input Fibonacci fixture, identical input 35, an opaque input barrier and result sink, and GCC 13.3. The host shim is compiled at GCC O2 in every cell.

Seven samples per cell, two untimed kernel executions before each timed call, deterministic shuffled sample order. Values are median milliseconds; the very short final row is diagnostic evidence, not a universal native/Wasm speed claim.

| Goose frontend | GCC | Median ms | MAD ms | Verified checksum |
| --- | --- | ---: | ---: | ---: |
| O0 | O0 | 61.366 | 3.078 | 9227465 |
| O0 | O2 | 16.810 | 1.109 | 9227465 |
| O2 | O0 | 68.769 | 3.449 | 9227465 |
| O2 | O2 | 0.204 | 0.013 | 9227465 |

The large gain depends on the combination of the two optimizers. Goose-O2 alone does not produce the final recurrence in its generated C. Its compiler log records zero full-function inlines, two base-case inlines, and zero tail-loop rewrites. The emitted C still has the two ordinary recursive terms, with explicit base-case guards around the calls.

GCC's [inline report](O2-O2.inline.txt) explicitly records recursive inlining of `kernel_g`. The [optimized GIMPLE](O2-O2.kernel.gimple.txt) and [machine code](O2-O2.disassembly.txt) show reuse of overlapping recursive results plus an accumulator loop. We do not attribute the entire sequence to a single named GCC pass.

For the generic path (n ≥ 7) in the retained machine code, the effective structure is:

```text
a = F(n - 3)
b = F(n - 4)
c = F(n - 5)
accumulator += a + 3*b + 2*c
n -= 4
repeat
```

The loop supplies the remaining F(n−4), so this computes the identity F(n)=F(n−3)+4F(n−4)+2F(n−5). Reusing b and c saves recursive work. It still performs overlapping recursion: there is no global memoization table, and it has not become a linear-time iterative Fibonacci implementation.

## Derived call-count model

A small model of the previously retained baseline assembly predicts the following function activation counts for input 35. These are derived counts, not instrumented execution counts or timings:

| Model | Kernel activations per F(35) evaluation |
| --- | ---: |
| Fully naive recursion | 29,860,703 |
| Base-case inlining only | 14,930,351 |
| Retained native machine-code model | 87,113 |

The model is implemented in [fibonacci_diagnostic.py](../../../fibonacci_diagnostic.py). Its native base counts for n = 0..4, 5, and 6 are 1, 2, and 4 respectively; for n ≥ 7 the activation recurrence is C(n) = C(n−3) + 2C(n−4) + C(n−5). This captures the three recursive calls and the loop replacing one additional call.

The original [dynamic-input audit](../fibonacci-audit.md) places the calculation between the two timestamps and validates several different runtime inputs. This follow-up additionally preserves C and GCC optimization evidence. The work was not replaced by a fixed answer.

Other benchmarks with already iterative loops have much less overlapping recursive work to remove. Fibonacci therefore remains useful as an optimization-sensitive workload, but its native/Wasm ratio should not be generalized to application performance.

## Reproduction and evidence

```sh
python bench/fibonacci_diagnostic.py --samples 7
```

- [Raw measurements, commands, versions and hashes](report.json)
- [Goose-O0 kernel](goose-O0.kernel.c) and [Goose-O2 kernel](goose-O2.kernel.c)
- [Complete diagnostic source/log archive](diagnostic-sources.tar.gz)

The generated code and imported runtime retain the repository/upstream Apache-2.0 license. The report identifies the compiler used for this follow-up; the original baseline report remains unchanged.

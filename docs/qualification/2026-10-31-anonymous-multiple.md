# Anonymous multiple-result and call-order qualification

Implementation: `5fdfa5f`.
Release compiler SHA-256: `80fe32716e55817d36665d76a3107f658bd38622b09d3f41e31677ae483466bb`.
Debug compiler SHA-256: `4ddc8db5dad277caedd1fdce518866e832871010424e63ef31a26a1e4bc7ef12`.
Prepared Release headers match that implementation commit byte-for-byte.

- Full Release differential suite: **1313/1313 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three explicit compile refusals.
- Debug temporary cases: **30/30**. Resource suites: **27/27** on both builds;
  the recursion case also reran with observable producer counters.
- Compiler sessions: **11/11** on Debug. Release backend extensions: **100/100**;
  static-data checks: **4/4**; scalar-cache checks: **13/13**.

Ordinary calls acquire anonymous owned result channels after evaluating arguments.
The recursion regressions cover single and mixed/multiple results used as
statements, including an ordinary callee eligible for inlining outside recursion.
Repeated exported calls release every owned output region. Inline result order
remains the pinned native emitter's order, before its argument prelude.

The Release runner and cache fixture inventory were pinned to this implementation
while the following variable-array slice was developed. An initial cache run used
that newer inventory and rejected its two variable-array cases; rerunning with
the matching inventory passed. The refusal fixture now uses a narrow variable
length, still outside this implementation's scope.

Reports and logs: `build/anonymous-order-*`. No broader language-parity claim.
